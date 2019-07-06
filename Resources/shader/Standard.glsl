//pref
ambient|float|0.0|1.0|1|Illuminate surface regardless of lighting
diffuse|float|0.0|0.2|1|Illuminate surface based on light position
specular|float|0.0|0.2|1|Glint from shiny surfaces
shininess|float|0.01|10.0|30|Specular reflections can be rough or precise
overlayFuzzy|float|0.01|0.5|1|Do overlay layers have blurry surfaces?
overlayDepth|float|0.0|0.3|0.8|Can we see overlay layers deep beneath the background image?
overlayClip|float|0|0|1|Does clipping also influence overlay layers?
//vert
#version 330 core
layout(location = 0) in vec3 vPos;
out vec3 TexCoord1;
out vec4 vPosition;
uniform mat4 ModelViewProjectionMatrix;
void main() {
  TexCoord1 = vPos;
  gl_Position = ModelViewProjectionMatrix * vec4(vPos, 1.0);
  vPosition = gl_Position;
}
//frag
#version 330 core
in vec3 TexCoord1;
out vec4 FragColor;
in vec4 vPosition;
uniform int loops;
uniform float stepSize, sliceSize;
uniform sampler3D intensityVol, gradientVol;
uniform sampler3D intensityOverlay, gradientOverlay;
uniform vec3 lightPosition, rayDir;
uniform vec4 clipPlane;
uniform float ambient = 1.0;
uniform float diffuse = 0.3;
uniform float specular = 0.25;
uniform float shininess = 10.0;
uniform float overlayDepth = 0.3;
uniform float overlayFuzzy = 0.5;
uniform int overlays = 0;
uniform float backAlpha = 0.5;
uniform float overlayClip = 0.0;
vec3 GetBackPosition (vec3 startPosition) { //when does ray exit unit cube http://prideout.net/blog/?p=64
	vec3 invR = 1.0 / rayDir;
    vec3 tbot = invR * (vec3(0.0)-startPosition);
    vec3 ttop = invR * (vec3(1.0)-startPosition);
    vec3 tmax = max(ttop, tbot);
    vec2 t = min(tmax.xx, tmax.yz);
	return startPosition + (rayDir * min(t.x, t.y));
}
void main() {
    vec3 start = TexCoord1.xyz;
	vec3 backPosition = GetBackPosition(start);
	vec3 dir = backPosition - start;
	float len = length(dir);
	dir = normalize(dir);
	vec3 deltaDir = dir * stepSize;
	vec4 gradSample, colorSample;
	float bgNearest = len; //assume no hit
	float overNearest = bgNearest;

	vec4 overAcc = vec4(0.0,0.0,0.0,0.0);
	vec4 colAcc = vec4(0.0,0.0,0.0,0.0);
	vec4 prevGrad = vec4(0.0,0.0,0.0,0.0);
	float lengthAcc = 0.0;
	//overlay pass
	vec3 startPos = start.xyz +deltaDir* (fract(sin(gl_FragCoord.x * 12.9898 + gl_FragCoord.y * 78.233) * 43758.5453));
	vec3 samplePos = startPos;
	float lenClip = len;
	if (clipPlane.a > -0.5) {
		bool frontface = (dot(dir , clipPlane.xyz) > 0.0);
		float dis = dot(dir,clipPlane.xyz);
		if (dis != 0.0  )  dis = (-clipPlane.a - dot(clipPlane.xyz, start.xyz-0.5)) / dis;
		//test: "return" fails on 2006MacBookPro10.4ATI1900, "discard" fails on MacPro10.5NV8800
		if (((frontface) && (dis >= len)) || ((!frontface) && (dis <= 0.0)))
			lengthAcc = len + 1.0; //no background
		else if ((dis > 0.0) && (dis < len)) {
			if (frontface) {
				lengthAcc = dis;
				//stepSizeX2 = dis;
				startPos += dir * dis;
				//len -= dir * dis;
			} else {
				backPosition =  start + dir * (dis);
				lenClip = length(backPosition - start);
			}
		}
	}
	float startLength = lengthAcc;
	float stepSizeX2 = -1.0;

	if ( overlays > 0.5 ) {
		//samplePos = startPos;
		lengthAcc = 0;
		if (overlayClip > 0) {
			samplePos = startPos;
			lengthAcc = startLength;
			stepSizeX2 = lengthAcc + (stepSize * 2.0);
			len = lenClip;
		}
		while (lengthAcc <= len) {
			colorSample = texture(intensityOverlay,samplePos);
			colorSample.a = 1.0-pow((1.0 - colorSample.a), stepSize/sliceSize);
			colorSample.a *=  overlayFuzzy;
			vec3 a = colorSample.rgb * ambient;
			float s =  0;
			vec3 d = vec3(0.0, 0.0, 0.0);
			if (colorSample.a > 0.0) {
				bgNearest = min(lengthAcc,bgNearest);
				//gradient based lighting http://www.mccauslandcenter.sc.edu/mricrogl/gradients
				if (lengthAcc > stepSizeX2) {
					gradSample = texture(gradientOverlay,samplePos); //interpolate gradient direction and magnitude
					gradSample.rgb = normalize(gradSample.rgb*2.0 - 1.0);
					//reusing Normals http://www.marcusbannerman.co.uk/articles/VolumeRendering.html
					if (gradSample.a < prevGrad.a)
						gradSample.rgb = prevGrad.rgb;
					prevGrad = gradSample;
					float lightNormDot = dot(gradSample.rgb, lightPosition);
					d = max(lightNormDot, 0.0) * colorSample.rgb * diffuse;
					s =   specular * pow(max(dot(reflect(lightPosition, gradSample.rgb), dir), 0.0), shininess);
				}

			}
			colorSample.rgb = a + d + s;
			colorSample.rgb *= colorSample.a;
			colAcc= (1.0 - colAcc.a) * colorSample + colAcc;
			samplePos += deltaDir;
			lengthAcc += stepSize;
			if ( lengthAcc >= len || colAcc.a > 0.95 )
				break;
		} //while lengthAcc < len
		colAcc.a = colAcc.a/0.95;
		overAcc = colAcc; //color accumulated by overlays
		overNearest = bgNearest;
		//clear values for background
		colAcc = vec4(0.0,0.0,0.0,0.0);
		prevGrad = vec4(0.0,0.0,0.0,0.0);
		lengthAcc = 0.0;
	} //if overlayNum > 0
	bgNearest = len; //assume no hit
	//end ovelay pass clip plane applied to background ONLY...
	samplePos = startPos;
	lengthAcc = startLength;
	stepSizeX2 = lengthAcc + (stepSize * 2.0);
	len = lenClip;
	while (lengthAcc <= len) {
		colorSample = texture(intensityVol,samplePos);
		colorSample.a = 1.0-pow((1.0 - colorSample.a), stepSize/sliceSize);
		vec3 a = colorSample.rgb * ambient;
		float s =  0;
		vec3 d = vec3(0.0, 0.0, 0.0);
		if (colorSample.a > 0.01) {
			bgNearest = min(lengthAcc,bgNearest);
			//gradient based lighting http://www.mccauslandcenter.sc.edu/mricrogl/gradients
			if (lengthAcc > stepSizeX2) {
				gradSample= texture(gradientVol,samplePos);
				gradSample.rgb = normalize(gradSample.rgb*2.0 - 1.0);
				//reusing Normals http://www.marcusbannerman.co.uk/articles/VolumeRendering.html
				if (gradSample.a < prevGrad.a)
					gradSample.rgb = prevGrad.rgb;
				prevGrad = gradSample;
				float lightNormDot = dot(gradSample.rgb, lightPosition);
				d = max(lightNormDot, 0.0) * colorSample.rgb * diffuse;
				s =   specular * pow(max(dot(reflect(lightPosition, gradSample.rgb), dir), 0.0), shininess);
			}
		}
		colorSample.rgb = a + d + s;
		colorSample.rgb *= colorSample.a;
		colAcc= (1.0 - colAcc.a) * colorSample + colAcc;
		samplePos += deltaDir;
		lengthAcc += stepSize;
		if ( lengthAcc >= len || colAcc.a > 0.95 )
			break;
	} //while lengthAcc < len
	colAcc.a = colAcc.a/0.95;
	colAcc.a *= backAlpha;
	//if (overAcc.a > 0.0) { //<- conditional not required: overMix always 0 for overAcc.a = 0.0
		float overMix = overAcc.a;
		if ((overNearest > bgNearest) && (colAcc.a > 0.0)) { //background (partially) occludes overlay
			//max distance between two vertices of unit cube is 1.73
			float dx = (overNearest - bgNearest)/1.73;
			dx = colAcc.a * pow(dx, overlayDepth);
			overMix *= 1.0 - dx;
		}
		colAcc.rgb = mix(colAcc.rgb, overAcc.rgb, overMix);
		colAcc.a = max(colAcc.a, overAcc.a);
	//}
    FragColor = colAcc;
}