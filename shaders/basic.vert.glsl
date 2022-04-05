#version 330 core

layout (location = 0) in vec3 inPosition;

uniform mat4 mvp;

void main()
{
    gl_Position = mvp * inPosition;
}