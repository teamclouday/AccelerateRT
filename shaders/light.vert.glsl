#version 450 core

layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal;

layout (location = 0) out vec3 vertNormal;
layout (location = 1) out vec3 fragPos;
layout (location = 2) out vec3 colNormal;

uniform mat4 mProjView;
uniform mat4 mModel;
uniform mat4 mNormal;

void main()
{
    colNormal = inNormal * 0.5 + 0.5;
    vertNormal = (mNormal * vec4(inNormal, 0.0)).xyz;
    vec4 fragPosition = mModel * vec4(inPosition, 1.0);
    fragPos = fragPosition.xyz;
    gl_Position = mProjView * fragPosition;
}