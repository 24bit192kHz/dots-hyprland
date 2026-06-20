#version 440

layout(location = 0) in vec2 coord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float utcDaysMod;
    float cameraTilt;
    float time;
    float gmst;
    float sunRa;
    float sunDec;
    float userLonRad;
    float userOffsetAngle;
    vec4 patchBounds;
    float patchReady;
    float cloudOpacity;
};

layout(binding = 1) uniform sampler2D earthTex;
layout(binding = 2) uniform sampler2D cloudTex;
layout(binding = 3) uniform sampler2D nightTex;
layout(binding = 4) uniform sampler2D bumpTex;
layout(binding = 5) uniform sampler2D waterTex;
layout(binding = 6) uniform sampler2D patchTex;

#define PI 3.14159265359

vec3 rotateX(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

float fract_safe(float v) {
    return v - floor(v);
}

// Simple 2D hash for noise
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// 2D Value Noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    float x = coord.x * 2.0 - 1.0;
    float y = 1.0 - coord.y * 2.0;
    
    float z2 = 1.0 - x*x - y*y;
    if (z2 < 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    float z = sqrt(z2);
    vec3 sphereNorm = vec3(x, y, z);
    
    // Rotate the geometric normal by cameraTilt to allow looking at the poles
    vec3 earthNorm = rotateX(sphereNorm, -cameraTilt);

    // The Earth's True North Pole in Equatorial Coordinates is simply (0, 1, 0).
    vec3 np = vec3(0.0, 1.0, 0.0);

    // Local Apparent Sidereal Time of the pixel at the center of the screen
    float localSiderealTime = gmst + userLonRad - userOffsetAngle;

    // Convert Sun's Right Ascension and Declination to local Cartesian vectors
    float sunLocalRa = sunRa - localSiderealTime;
    float cosSD = cos(sunDec);
    vec3 sunVec = normalize(vec3(sin(sunLocalRa) * cosSD, sin(sunDec), cos(sunLocalRa) * cosSD));

    // Calculate Greenwich's vector
    float greenwichLocalRa = gmst - localSiderealTime;
    float sinG = sin(greenwichLocalRa);
    float cosG = cos(greenwichLocalRa);
    vec3 greenwichVec = normalize(vec3(sinG, 0.0, cosG));
    vec3 eastVec = normalize(vec3(cos(greenwichLocalRa), 0.0, -sinG));
    
    vec3 eqPlane = earthNorm - dot(earthNorm, np) * np;
    float eqLen = length(eqPlane);
    eqPlane = eqPlane / max(0.0001, eqLen);
    
    // Longitude and Latitude
    float absoluteLon = atan(dot(eqPlane, eastVec), dot(eqPlane, greenwichVec));
    float cloudLon = absoluteLon + (utcDaysMod * 0.06 * PI);
    float earthLat = asin(dot(earthNorm, np));

    vec2 earthUV = vec2(fract_safe(absoluteLon / (2.0 * PI) + 0.5), 0.5 - earthLat / PI);
    vec2 cloudUV = vec2(fract_safe(cloudLon / (2.0 * PI) + 0.5), earthUV.y);

    // Wrap-safe derivatives for mipmap selection
    vec2 dx = dFdx(earthUV);
    vec2 dy = dFdy(earthUV);
    if (abs(dx.x) > 0.5) dx.x -= sign(dx.x);
    
    vec2 c_dx = dFdx(cloudUV);
    vec2 c_dy = dFdy(cloudUV);
    if (abs(c_dx.x) > 0.5) c_dx.x -= sign(c_dx.x);

    // Raw diffuse dot
    float nDotL = dot(earthNorm, sunVec);
    
    // ── Base Color ──
    vec3 earthColor = textureGrad(earthTex, earthUV, dx, dy).rgb;
    
    // ── Virtual Texturing Patch ──
    float patchU = earthUV.x;
    if (patchBounds.z > 1.0 && patchU < patchBounds.x) {
        patchU += 1.0;
    } else if (patchBounds.x < 0.0 && patchU > patchBounds.z) {
        patchU -= 1.0;
    }

    if (patchReady > 0.5 && patchBounds.z > patchBounds.x && patchU >= patchBounds.x && patchU <= patchBounds.z && earthUV.y >= patchBounds.y && earthUV.y <= patchBounds.w) {
        vec2 localUV = vec2(
            (patchU - patchBounds.x) / (patchBounds.z - patchBounds.x),
            (earthUV.y - patchBounds.y) / (patchBounds.w - patchBounds.y)
        );
        vec3 patchColor = textureGrad(patchTex, localUV, dx, dy).rgb;
        
        float edgeU = min(localUV.x, 1.0 - localUV.x);
        float edgeV = min(localUV.y, 1.0 - localUV.y);
        float blend = smoothstep(0.0, 0.05, min(edgeU, edgeV));
        
        earthColor = mix(earthColor, patchColor, blend);
    }
    
    // ── Surface Data ──
    float waterMask = textureGrad(waterTex, earthUV, dx, dy).r;
    float bump = textureGrad(bumpTex, earthUV, dx, dy).r;
    
    // ── Seamless Date Line Blending ──
    // Only runs for the ~0.1% of pixels right at the seam
    float seamDist = min(earthUV.x, 1.0 - earthUV.x);
    if (seamDist < 0.001) {
        float altX = earthUV.x < 0.5 ? 1.0 : 0.0;
        vec2 altUV = vec2(altX, earthUV.y);
        float seamBlend = 0.5 + 0.5 * (seamDist / 0.001);
        
        earthColor = mix(textureGrad(earthTex, altUV, dx, dy).rgb, earthColor, seamBlend);
        bump = mix(textureGrad(bumpTex, altUV, dx, dy).r, bump, seamBlend);
        waterMask = mix(textureGrad(waterTex, altUV, dx, dy).r, waterMask, seamBlend);
    }
    
    // ── Bump Mapping ──
    float bumpScale = 0.003 * (1.0 - waterMask);
    vec2 texel = vec2(1.0 / 8192.0, 1.0 / 4096.0);
    
    vec2 duUV = earthUV + vec2(texel.x, 0.0);
    duUV.x = fract_safe(duUV.x);
    vec2 dvUV = earthUV + vec2(0.0, texel.y);
    
    float bumpDu = textureGrad(bumpTex, duUV, dx, dy).r;
    float bumpDv = textureGrad(bumpTex, dvUV, dx, dy).r;
    
    if (seamDist < 0.001) {
        float altXdu = duUV.x < 0.5 ? 1.0 : 0.0;
        float blendDu = 0.5 + 0.5 * (min(duUV.x, 1.0 - duUV.x) / 0.001);
        bumpDu = mix(textureGrad(bumpTex, vec2(altXdu, duUV.y), dx, dy).r, bumpDu, blendDu);
        
        float altXdv = dvUV.x < 0.5 ? 1.0 : 0.0;
        float blendDv = 0.5 + 0.5 * (min(dvUV.x, 1.0 - dvUV.x) / 0.001);
        bumpDv = mix(textureGrad(bumpTex, vec2(altXdv, dvUV.y), dx, dy).r, bumpDv, blendDv);
    }
    
    float dbDu = (bumpDu - bump) / texel.x;
    float dbDv = (bumpDv - bump) / texel.y;
    
    // ── Procedural Ocean Waves ──
    if (waterMask > 0.1) {
        vec2 waveUV = earthUV * 15000.0;
        float wTime = time * 3.0;
        
        vec2 d1 = vec2(1.0, 0.5);
        vec2 d2 = vec2(-0.7, 0.8);
        vec2 d3 = vec2(0.3, -1.2);
        
        float p1 = dot(waveUV, d1) + wTime;
        float p2 = dot(waveUV, d2) * 1.6 + wTime * 1.3;
        float p3 = dot(waveUV, d3) * 2.4 + wTime * 0.7;
        
        float c1 = cos(p1), c2 = cos(p2), c3 = cos(p3);
        float dwDu = (c1 * d1.x + c2 * d2.x * 1.6 + c3 * d3.x * 2.4) * 0.1667;
        float dwDv = (c1 * d1.y + c2 * d2.y * 1.6 + c3 * d3.y * 2.4) * 0.1667;
        
        dbDu = mix(dbDu, dwDu * 0.8, waterMask);
        dbDv = mix(dbDv, dwDv * 0.8, waterMask);
        bumpScale = mix(bumpScale, 0.005, waterMask);
    }
    
    // Apply bump mapping
    vec3 bumpNorm = normalize(earthNorm - vec3(dbDu, dbDv, 0.0) * bumpScale);
    float bumpDiffuse = max(dot(bumpNorm, sunVec), 0.0);
    float diffuse = mix(max(nDotL, 0.0), bumpDiffuse, smoothstep(-0.1, 0.1, nDotL));

    // ── Specular ──
    vec3 viewVecTrue = rotateX(vec3(0.0, 0.0, 1.0), -cameraTilt);
    vec3 halfVec = normalize(sunVec + viewVecTrue);
    float specBase = max(dot(bumpNorm, halfVec), 0.0);
    float specular = pow(specBase, 35.0) * waterMask * 0.4;
    float softSpecular = pow(max(dot(earthNorm, halfVec), 0.0), 8.0) * 0.02;

    // ── Day Color ──
    vec3 dayColor = earthColor * diffuse + vec3(1.0, 0.95, 0.8) * specular + vec3(1.0) * softSpecular;

    // ── Atmospheric Scattering ──
    // Use sphereNorm.z instead of earthNorm.z so the atmosphere thickness is calculated 
    // in screen-space, independent of camera tilt.
    float atmosThickness = pow(1.0 - max(sphereNorm.z, 0.0), 3.5);
    
    float twilight = smoothstep(-0.05, 0.0, nDotL) * (1.0 - smoothstep(0.0, 0.05, nDotL));
    vec3 atmosColorBlue = vec3(0.3, 0.6, 1.0) * atmosThickness * smoothstep(-0.2, 0.5, nDotL) * 1.2;
    vec3 atmosColorOrange = vec3(1.0, 0.4, 0.1) * atmosThickness * twilight * 1.5;
    
    // ── Stratospheric Ozone Absorption ──
    float ozoneBand = smoothstep(-0.15, -0.05, nDotL) * (1.0 - smoothstep(0.0, 0.2, nDotL));
    vec3 ozoneColor = vec3(0.3, 0.1, 0.8) * atmosThickness * ozoneBand * 1.8;
    
    dayColor += atmosColorBlue + atmosColorOrange + ozoneColor;

    // ── Night City Lights ──
    vec3 nightColor = textureGrad(nightTex, earthUV, dx, dy).rgb * vec3(1.0, 0.9, 0.7);
    
    if (seamDist < 0.001) {
        float altX = earthUV.x < 0.5 ? 1.0 : 0.0;
        vec2 altUV = vec2(altX, earthUV.y);
        float seamBlend = 0.5 + 0.5 * (seamDist / 0.001);
        nightColor = mix(textureGrad(nightTex, altUV, dx, dy).rgb * vec3(1.0, 0.9, 0.7), nightColor, seamBlend);
    }
    nightColor *= 2.0;

    // ── Day/Night Transition ──
    float terminator = smoothstep(-0.15, 0.15, nDotL);
    vec3 color = mix(nightColor, dayColor, terminator);

    // ── Clouds ──
    // Multi-octave fluid noise (FBM) for realistic atmospheric flow
    float n1 = noise(cloudUV * 6.0 + time * 0.01);
    float n2 = noise(cloudUV * 12.0 - time * 0.02 + vec2(100.0));
    float n3 = noise(cloudUV * 24.0 + time * 0.03 + vec2(200.0));
    
    float flowX = n1 + 0.5 * n2 + 0.25 * n3;
    float flowY = n2 + 0.5 * n3 + 0.25 * n1;
    
    vec2 cloudWarp = vec2(
        (flowX - 0.875) * 0.015,
        (flowY - 0.875) * 0.005
    );
    
    vec2 warpedCloudUV = cloudUV + cloudWarp;
    float cloudSample = textureGrad(cloudTex, warpedCloudUV, c_dx, c_dy).r;
    float cloudAlpha = (cloudSample * 0.9) * cloudOpacity;
    
    // Cloud shadow — reuse the same sample with an offset instead of a second texture read
    vec2 shadowOffset = -sunVec.xy * 0.01;
    float cloudShadowAlpha = textureGrad(cloudTex, warpedCloudUV + shadowOffset, c_dx, c_dy).r * 0.9;
    float cloudShadow = 1.0 - (cloudShadowAlpha * smoothstep(0.0, 0.2, nDotL) * 0.4);
    
    color *= cloudShadow;
    
    // Cloud lighting
    float cloudLight = max(dot(earthNorm, sunVec), 0.0);
    vec3 cloudLitColor = mix(vec3(1.0, 0.6, 0.4), vec3(1.0), smoothstep(0.0, 0.3, nDotL));
    cloudLitColor *= cloudLight;
    cloudLitColor += vec3(0.1, 0.15, 0.2) * (1.0 - cloudLight);
    
    // ── Realistic Lightning Storms ──
    float darkSide = 1.0 - smoothstep(-0.2, 0.2, nDotL);
    
    // Calculate storm core density (lightning can ONLY exist inside dense clouds)
    float stormCore = smoothstep(0.65, 1.0, cloudSample);
    
    if (darkSide > 0.0 && stormCore > 0.0) {
        // High-resolution grid perfectly mapped to the fluid dynamics of the clouds
        vec2 stormGrid = warpedCloudUV * 100.0; 
        vec2 stormCell = floor(stormGrid);
        
        float cellHash = hash21(stormCell);
        
        // 60% of dense cloud cores are electrically active
        if (cellHash > 0.4) {
            vec2 stormFract = fract(stormGrid);
            
            // Randomize the exact center of the flash inside the localized storm cell
            vec2 flashCenter = vec2(hash21(stormCell + 1.2), hash21(stormCell + 3.4));
            float flashGlow = smoothstep(0.7, 0.0, length(stormFract - flashCenter));
            
            // Multi-stroke Strobe Physics:
            // Real lightning strikes in rapid bursts separated by long pauses.
            // 'stormCycle' creates the long pauses. 'strobe' creates the rapid flickering strokes.
            float stormCycle = time * 2.0 + cellHash * 100.0;
            float window = pow(max(sin(stormCycle), 0.0), 15.0); // Spikes briefly
            float strobe = pow(max(sin(time * 50.0 + cellHash * 20.0), 0.0), 2.0); // Rapid flicker
            
            float flash = window * strobe;
            
            // Colors: predominantly electric blue/white, with rare red/purple sprites
            vec3 flashColor = mix(vec3(0.5, 0.8, 1.0), vec3(0.9, 0.2, 1.0), step(0.98, hash21(stormCell + 7.7)));
            
            cloudLitColor += flashColor * (flash * flashGlow * stormCore * darkSide * 20.0);
        }
    }
    
    // Night side clouds obscure city lights
    color = mix(color, vec3(0.005), cloudAlpha * (1.0 - terminator));
    
    // Render clouds on top — on night side, clouds are nearly invisible (no sunlight)
    // Only lightning flashes provide glow through dark clouds
    vec3 nightCloudColor = vec3(0.005, 0.008, 0.012);
    vec3 finalCloudColor = mix(nightCloudColor, cloudLitColor, terminator);
    color = mix(color, finalCloudColor, cloudAlpha);
    
    fragColor = vec4(color, qt_Opacity);
}
