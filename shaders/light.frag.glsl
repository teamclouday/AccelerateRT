#version 450 core

layout (location = 0) out vec4 color;

layout (location = 0) in vec3 vertNormal;

uniform vec3 baseColor;

void main()
{
    // simple directional light
    const vec3 lightDir = normalize(vec3(1.0,1.0,1.0));
    float strength = max(dot(vertNormal, lightDir), 0.1);
    color = vec4(baseColor * strength, 1.0);
}