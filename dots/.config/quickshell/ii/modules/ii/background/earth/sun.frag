#version 440
layout(location = 0) in vec2 coord;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

void main() {
    vec2 uv = coord * 2.0 - 1.0;
    float r = length(uv);
    
    // Core: tight and blindingly white
    float core = smoothstep(0.08, 0.05, r);
    
    // Primary bloom (very bright, tight)
    float bloom1 = exp(-r * 15.0) * 2.0;
    
    // Secondary bloom (wide, soft)
    float bloom2 = exp(-r * 5.0) * 0.8;
    
    // Tertiary bloom (very wide, very subtle)
    float bloom3 = exp(-r * 2.0) * 0.3;
    
    // Extremely subtle, wide optical lens flare streaks (like a 4-point star lens filter)
    float a = atan(uv.y, uv.x);
    float star = pow(abs(cos(a * 2.0)), 16.0) * exp(-r * 4.0) * 0.15;
    
    // Pure, blinding white with the tiniest hint of warmth in the outer glow
    vec3 coreColor = vec3(1.0, 1.0, 1.0);
    vec3 glowColor = vec3(1.0, 0.98, 0.95); 
    
    float intensity = core + bloom1 + bloom2 + bloom3 + star;
    vec3 finalColor = glowColor * intensity;
    // Core always pure white
    finalColor = mix(finalColor, coreColor, core);
    
    // Smooth fade to transparent at the quad edges
    float alpha = min(intensity, 1.0) * smoothstep(1.0, 0.7, r);
    
    // Pre-multiplied alpha
    fragColor = vec4(finalColor * alpha, alpha * qt_Opacity);
}
