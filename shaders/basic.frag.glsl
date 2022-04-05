#version 330 core

layout (location = 0) out vec4 color;

uniform vec3 baseColor;

void main()
{
    color = vec4(baseColor, 1.0);
}