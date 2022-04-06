# some utils

using ModernGL, CSyntax
using .AccelerateRT: loadFileText

function getShaderInfo(obj)
    isShader = glIsShader(obj)
    getiv = isShader == GL_TRUE ? glGetShaderiv : glGetProgramiv
	getInfo = isShader == GL_TRUE ? glGetShaderInfoLog : glGetProgramInfoLog
    len::GLint = 0
    @c getiv(obj, GL_INFO_LOG_LENGTH, &len)
    if len > 0
        buffer = zeros(GLchar, len+1)
        @c getInfo(obj, len, &len, buffer)
        return unsafe_string(pointer(buffer), len)
    else
        return ""
    end
end

function createShader(source, type, isPath=false)
    if isPath
        source = loadFileText(source)
    end
    shader = glCreateShader(type)
    @assert shader != 0 "Failed to create shader!"
    glShaderSource(shader, 1, convert(Ptr{UInt8}, pointer([convert(Ptr{GLchar}, pointer(source))])), C_NULL)
    glCompileShader(shader)
    success::GLint = 0
    @c glGetShaderiv(shader, GL_COMPILE_STATUS, &success)
    if success != GL_TRUE
        error("Failed to create shader!\n$source\n", getShaderInfo(shader))
        glDeleteShader(shader)
    end
    return shader
end

function createShaderProgram(shaders::AbstractArray)
    prog = glCreateProgram()
    @assert prog != 0 "Failed to create shader program!"
    for shader in shaders
        glAttachShader(prog, shader)
    end
    glLinkProgram(prog)
    success::GLint = 0
    @c glGetProgramiv(prog, GL_LINK_STATUS, &success)
    if success != GL_TRUE
        error("Failed to create shader program!\n", getShaderInfo(prog))
        glDeleteProgram(prog)
    end
    return prog
end

function glDebugCallback(source, type, id, severity, length, message, userParam)
    println("**** GL Callback ****")
    print("(",
        severity == GL_DEBUG_SEVERITY_HIGH ? "High" :
        severity == GL_DEBUG_SEVERITY_LOW ? "Low" :
        severity == GL_DEBUG_SEVERITY_MEDIUM ? "Med" :
        severity == GL_DEBUG_SEVERITY_NOTIFICATION ? "Noti" : "",
        ") ")
    print("<",
        source == GL_DEBUG_SOURCE_API ? "API" :
        source == GL_DEBUG_SOURCE_APPLICATION ? "Application" :
        source == GL_DEBUG_SOURCE_OTHER ? "Other" :
        source == GL_DEBUG_SOURCE_SHADER_COMPILER ? "Shader Compiler" :
        source == GL_DEBUG_SOURCE_THIRD_PARTY ? "Third Party" :
        source == GL_DEBUG_SOURCE_WINDOW_SYSTEM ? "Window System" : "",
        "> ")
    print("[",
        type == GL_DEBUG_TYPE_ERROR ? "Error" :
        type == GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR ? "Deprecated Behaviour" :
        type == GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR ? "Undefined Behaviour" : 
        type == GL_DEBUG_TYPE_PORTABILITY ? "Portability" :
        type == GL_DEBUG_TYPE_PERFORMANCE ? "Performance" :
        type == GL_DEBUG_TYPE_MARKER ? "Marker" :
        type == GL_DEBUG_TYPE_PUSH_GROUP ? "Push Group" :
        type == GL_DEBUG_TYPE_POP_GROUP ? "Pop Group" :
        type == GL_DEBUG_TYPE_OTHER ? "Other" : "",
        "] ")
    
    println(unsafe_string(message))
end

const glDebugCallbackC = @cfunction(glDebugCallback, Cvoid, (GLenum, GLenum, GLuint, GLenum, GLsizei, Ptr{GLchar}, Ptr{Cvoid}))