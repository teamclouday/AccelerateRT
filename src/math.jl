# basic math utils for graphics

using StaticArrays: MVector, MMatrix, FieldVector
using LinearAlgebra: cross, normalize

const DataType = Union{Float32, Int32}

const Vector2{DataType} = MVector{2, DataType}
const Vector3{DataType} = MVector{3, DataType}
const Vector4{DataType} = MVector{4, DataType}
const Color3{DataType} = MVector{3, DataType}
const Color4{DataType} = MVector{4, DataType}
const Matrix3x3{DataType} = MMatrix{3, 3, DataType}
const Matrix4x4{DataType} = MMatrix{4, 4, DataType}

function emptyMatrix3x3(type)::Matrix3x3
    return Matrix3x3{type}(
        0,0,0,
        0,0,0,
        0,0,0)
end

function identityMatrix3x3(type)::Matrix3x3
    return Matrix3x3{type}(
        1,0,0,
        0,1,0,
        0,0,1)
end

function emptyMatrix4x4(type)::Matrix4x4
    return Matrix4x4{type}(
        0,0,0,0,
        0,0,0,0,
        0,0,0,0,
        0,0,0,0)
end

function identityMatrix4x4(type)::Matrix4x4
    return Matrix4x4{type}(
        1,0,0,0,
        0,1,0,0,
        0,0,1,0,
        0,0,0,1)
end

function computeNormal(v1::Vector3, v2::Vector3, v3::Vector3)::Vector3
    dir = cross(v2 - v1, v3 - v1)
    return normalize(dir)
end

# matrix transformations are learned from glm implementations
# refer to: https://github.com/Groovounet/glm

function computeProjection(fov::T, ratio::T, near::T, far::T)::Matrix4x4 where T<:DataType
    fovHalf = tan(deg2rad(fov) / T(2.0))
    mat = emptyMatrix4x4(T)
    one = T(1)
    mat[2,2] = one / fovHalf
    mat[1,1] = mat[2,2] / ratio
    mat[3,3] = (far + near) / (near - far)
    mat[3,4] = -one
    mat[4,3] = (one * 2 * far * near) / (near - far)
    return mat
end

function computeTranslate(t::Vector3{T})::Matrix4x4 where T<:DataType
    mat = identityMatrix4x4(T)
    return computeTranslate(mat, t)
end

function computeTranslate(mat::Matrix4x4{T}, t::Vector3{T})::Matrix4x4 where T<:DataType
    res = copy(mat)
    res[:, 4] = mat[:, 1] * t[1] + mat[:, 2] * t[2] + mat[:, 2] * t[2] + mat[:, 3]
    return res
end

function computeRotation(angle::T, v::Vector3{T})::Matrix4x4 where T<:DataType
    mat = identityMatrix4x4(T)
    return computeRotation(mat, angle, v)
end

function computeRotation(mat::Matrix4x4{T}, angle::T, v::Vector3{T})::Matrix4x4 where T<:DataType
    a = deg2rad(angle)
    c = cos(a)
    s = sin(a)
    one = T(1)
    axis = normalize(v)
    temp = (one - c) * axis
    rot = emptyMatrix3x3(T)
    rot[:, 1] = [
    c + temp[1] * axis[1],
        temp[1] * axis[2] + s * axis[3],
        temp[1] * axis[3] - s * axis[2]
    ]
    rot[:, 2] = [
        temp[2] * axis[1] - s * axis[3],
    c + temp[2] * axis[2],
        temp[2] * axis[3] + s * axis[1]
    ]
    rot[:, 3] = [
        temp[3] * axis[1] + s * axis[2],
        temp[3] * axis[2] - s * axis[3],
    c + temp[3] * axis[3]
    ]
    res = copy(mat)
    res[:, 1] = mat[:, 1] * rot[1,1] + mat[:, 2] * rot[2,1] + mat[:, 3] * rot[3,1]
    res[:, 2] = mat[:, 1] * rot[1,2] + mat[:, 2] * rot[2,2] + mat[:, 3] * rot[3,2]
    res[:, 3] = mat[:, 1] * rot[1,3] + mat[:, 2] * rot[2,3] + mat[:, 3] * rot[3,3]
    return res
end

function computeScale(s::Vector3{T})::Matrix4x4 where T<:DataType
    mat = identityMatrix4x4(T)
    return computeScale(mat, s)
end

function computeScale(mat::Matrix4x4{T}, s::Vector3{T})::Matrix4x4 where T<:DataType
    res = copy(mat)
    res[:, 1] = mat[:, 1] * s[1]
    res[:, 2] = mat[:, 2] * s[2]
    res[:, 3] = mat[:, 3] * s[3]
    return res
end