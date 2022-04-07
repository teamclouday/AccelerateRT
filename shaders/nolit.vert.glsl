#version 450 core

layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal;

layout (location = 0) out vec3 colNormal;

uniform mat4 mProjView;
uniform mat4 mModel;

void main()
{
    colNormal = inNormal * 0.5 + 0.5;
    gl_Position = mProjView * mModel * vec4(inPosition, 1.0);
}