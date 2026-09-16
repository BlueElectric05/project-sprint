shader_type sky;

uniform vec3 top_color : source_color = vec3(0.0, 0.2, 0.8);
uniform vec3 bottom_color : source_color = vec3(0.9, 0.6, 0.1);

void sky() {
    // 1. Calculate the vertical gradient based on the camera angle
    // EYEDIR.y maps from 0.0 (horizon) to 1.0 (straight up)
    float t = clamp(EYEDIR.y, 0.0, 1.0);
    
    // 2. Mix the two colors together smoothly
    vec3 smooth_color = mix(bottom_color, top_color, t);
    
    // 3. Quantize the color down to 5-bit (32 shades per channel)
    // We multiply by 31, round to the nearest whole number, then divide by 31
    vec3 retro_color = round(smooth_color * 31.0) / 31.0;
    
    COLOR = retro_color;
}