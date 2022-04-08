#version 450 core

layout (location = 0) in vec4 inPosition;

layout (location = 0) out float multiplier;

uniform mat4 mvp;
uniform float thresL;
uniform float thresR;

void main()
{
    multiplier = ((inPosition.w < thresR + 1e-5) && (inPosition.w > thresL - 1e-5)) ? 1.0 : 0.0;
    gl_Position = mvp * vec4(inPosition.xyz, 1.0);
}