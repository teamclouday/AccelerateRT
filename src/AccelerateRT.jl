module AccelerateRT

export Vector2, Vector3, Vector4, Color3, Color4,
    Matrix3x3, Matrix4x4, emptyMatrix3x3, identityMatrix3x3,
    emptyMatrix4x4, identityMatrix4x4, computeNormal,
    computeProjection, computeView, computeTranslate,
    computeRotation, computeScale
export ModelData, describeModel
export loadFileText, loadFileBinary, loadObjFile
export Camera, updateCamera!, processMouse!, processWheel!, processKey!
export createShader, createShaderProgram, glDebugCallbackC

include("math.jl")
include("model.jl")
include("files.jl")
include("camera.jl")
include("utils.jl")
include("algorithms/Algorithms.jl")

end