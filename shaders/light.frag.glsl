#version 450 core

layout (location = 0) out vec4 color;

layout (location = 0) in vec3 vertNormal;

uniform vec3 baseColor;

void main()
{
    // simple directional light
    const vec3 lightDir = normalize(vec3(1.0,1.0,1.0));
    const vec3 lightColor = vec3(1.0, 244.0 / 255.0, 214.0 / 255.0);
    float strength = max(dot(vertNormal, lightDir), 0.0);
    color = vec4(baseColor * strength * lightColor + baseColor * 0.25, 1.0);
}