#version 450 core

layout (location = 0) out vec4 color;

layout (location = 0) in float multiplier;

uniform vec4 baseColor;

void main()
{
    color = baseColor * multiplier;
}