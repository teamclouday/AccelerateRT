#version 450 core

layout (location = 0) out vec4 color;

layout (location = 0) in vec3 vertNormal;
layout (location = 1) in vec3 fragPos;
layout (location = 2) in vec3 colNormal;

uniform vec3 baseColor;
uniform vec3 viewPos;
uniform float useNormalColor;

void main()
{
    // simple directional light
    const vec3 lightDir = normalize(vec3(1.0,1.0,1.0));
    const vec3 lightColor = vec3(1.0, 244.0 / 255.0, 214.0 / 255.0);
    // apply diffuse
    float diff = max(dot(vertNormal, lightDir), 0.0);
    // apply specular
    vec3 viewDir = normalize(viewPos - fragPos);
    vec3 reflectDir = reflect(-lightDir, vertNormal);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32);
    // collect color
    color = vec4(0.0,0.0,0.0,1.0);
    color.rgb = 0.25 + // ambiant
        lightColor * diff + // diffuse
        lightColor * spec; // specular
    if(useNormalColor > 0.0)
    {
        color.rgb *= colNormal;
    }
    else
    {
        color.rgb *= baseColor;
    }
}