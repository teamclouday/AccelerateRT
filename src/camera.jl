# virtual camera

using LinearAlgebra: normalize, cross, norm
using .AccelerateRT: Vector3, Matrix4x4

const WorldUp = Vector3{Float32}(0.0, 1.0, 0.0)

mutable struct Camera
    fov::Float32
    near::Float32
    far::Float32
    sensTurn::Float32
    sensMove::Float32
    dist::Float32
    ratio::Float32
    lockCenter::Bool
    p_pos::Vector3
    p_up::Vector3
    p_right::Vector3
    p_front::Vector3
    p_center::Vector3
    Camera(;pos::Vector3, center::Vector3) = begin
        new(45.0, 0.1, 1000.0, 0.1, 1.0, 0.0, 1.0, true,
            pos, Vector3{Float32}(0.0, 1.0, 0.0),
            Vector3(0.0f0), Vector3(0.0f0), center)
        # remember to call updateCamera after construction!
    end
end

function updateCamera!(camera::Camera)
    camera.p_front = normalize(camera.p_center - camera.p_pos)
    camera.p_right = normalize(cross(camera.p_front, WorldUp))
    camera.p_up = normalize(cross(camera.p_right, camera.p_front))
    camera.dist = norm(camera.p_center - camera.p_pos)
end

function processMouse!(camera::Camera, deltaX::Float32, deltaY::Float32, left::Bool, right::Bool)
    if iszero(deltaX) && iszero(deltaY)
        return
    end
    if !left && !right
        return
    end
    if left
        dX = deltaX * camera.sensTurn
        dY = deltaY * camera.sensTurn
        v1 = camera.lockCenter ? camera.p_pos : camera.p_center
        v2 = camera.lockCenter ? camera.p_center : camera.p_pos
        dir = Vector3{Float32}((
            computeRotation(dX, WorldUp) *
            Vector4{Float32}(normalize(v1 - v2)..., 0))[1:3]...)
        tmp = Vector3{Float32}((
            computeRotation(dY, camera.p_right) *
            Vector4{Float32}(dir..., 0))[1:3]...)
        if tmp.x * dir.x > 1f-5
            dir .= tmp
        end
        v1 .= v2 + dir * camera.dist
    end
    if right
        dX = -deltaX * camera.sensMove * 0.001f0
        dY = -deltaY * camera.sensMove * 0.001f0
        trans = computeTranslate(dY * camera.p_up) * computeTranslate(-dX * camera.p_right)
        camera.p_center = Vector3{Float32}((trans * Vector4{Float32}(camera.p_center..., 1))[1:3]...)
        camera.p_pos    = Vector3{Float32}((trans * Vector4{Float32}(camera.p_pos..., 1))[1:3]...)
    end
    updateCamera!(camera)
end

function processWheel!(camera::Camera, delta::Float32)
    if camera.dist + delta > 1f-2
        camera.dist += delta
        camera.p_pos = camera.p_center - camera.p_front * camera.dist
    end
end

function processKey!(camera::Camera, deltaFront::Float32, deltaRight::Float32)
    if iszero(deltaFront) && iszero(deltaRight)
        return
    end
    delta = camera.p_front * deltaFront + camera.p_right * deltaRight
    camera.p_pos += delta
    if !camera.lockCenter
        camera.p_center += delta
    else
        updateCamera!(camera)
    end
end