#version 450 core

layout (location = 0) out vec4 color;

layout (location = 0) in vec3 colNormal;

uniform vec3 baseColor;
uniform float useNormalColor;

void main()
{
    if(useNormalColor > 0.0)
    {
        color = vec4(colNormal, 1.0);
    }
    else
    {
        color = vec4(baseColor, 1.0);
    }
}