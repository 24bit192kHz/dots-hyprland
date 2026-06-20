#version 440

layout(location = 0) in vec2 coord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float localSiderealTime;
    float userTiltOffset;
    float aspect;
};

layout(binding = 1) uniform sampler2D bgTex;

const float PI  = 3.14159265359;
const float TAU = 6.28318530718;

vec3 rotateX(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

vec3 rotateY(vec3 p, float a) {
    float c = cos(a), s = sin(a);
    return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}

vec2 sphereToUV(vec3 p) {
    float lon = atan(p.x, p.z);
    float lat = asin(clamp(p.y, -1.0, 1.0));
    // Milky Way texture typically needs to be flipped or shifted, but this works generally
    return vec2(lon / TAU + 0.5, 0.5 - lat / PI);
}

void main() {
    vec2 ndc = coord * 2.0 - 1.0;
    ndc.x *= aspect;
    
    // 90 degree FOV (z = -1.0)
    vec3 ray = normalize(vec3(ndc.x, -ndc.y, -1.5)); // Zoomed slightly to reduce distortion
    
    // Apply camera tilt (with 1:10 parallax effect so it moves at 1x speed despite 10x orbit)
    ray = rotateX(ray, userTiltOffset * 0.1);
    
    // Apply sidereal rotation (with 1:10 parallax effect)
    ray = rotateY(ray, -localSiderealTime * 0.1);
    
    vec2 bgUV = sphereToUV(ray);
    fragColor = texture(bgTex, bgUV) * qt_Opacity;
}
