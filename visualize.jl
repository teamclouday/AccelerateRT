# load and visualize a BVH

using ArgParse, Printf, CSyntax
using GLFW, ModernGL, CImGui

include("src/AccelerateRT.jl")
using .AccelerateRT

const APPNAME   = "AccelerateRT"
const APPWIDTH  = 800
const APPHEIGHT = 600

function parseCommandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "model"
            help = "obj model path"
            required = true
    end
    return parse_args(s)
end

function main()
    args = parseCommandline()
    modelPath = args["model"]
    model = loadObjFile(modelPath)
    describeModel(model)
    app = initApp(model)
    renderData = loadRenderData(app)
    renderLoop(app, renderData)
    destroyApp(app)
end

mutable struct Configs
    showUI # where to show UI
    keyDown # which keys in WASD are down
    mousePos # current mouse position
    mouseDown # which mouse buttons are down
    imguiFocus # is UI in focus
    winW # window width
    winH # window height
    background::Color4 # background color
    wireframe # whether is wireframe mode
    gldebug # whether to output OpenGL debug info
    Configs() = begin
        new(true, [false, false, false, false],
            [-1.0,0.0,0.0,0.0], [false, false],
            false, APPWIDTH, APPHEIGHT,
            Color4{Float32}(0,0,0,1), false, false)
    end
end

mutable struct Application
    window
    imgui
    camera
    model
    configs
end

mutable struct RenderData
    VAO
    VBO
    pNolit # nolit shader program
    pLight # light shader program
    color::Color3 # model base color
    tTrans::Vector3 # model translation
    tRotScale::Vector2 # model rotation (around Y axis) & scale
    enableLight
end

function renderLoop(app, renderData)
    while !GLFW.WindowShouldClose(app.window)
        app.configs.winW, app.configs.winH = GLFW.GetFramebufferSize(app.window)
        if app.configs.wireframe
            glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
        else
            glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
        end
        glViewport(0, 0, app.configs.winW, app.configs.winH)
        glClearColor(app.configs.background...)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        # render model
        mvp = computeProjection(app.camera.fov, app.camera.ratio, app.camera.near, app.camera.far) *
            computeView(app.camera.p_pos, app.camera.p_center, app.camera.p_up) *
            computeScale(computeRotation(computeTranslate(renderData.tTrans), renderData.tRotScale.x, Vector3{Float32}(0,1,0)),
                Vector3{Float32}(renderData.tRotScale.y, renderData.tRotScale.y, renderData.tRotScale.y))
        prog = renderData.enableLight ? renderData.pLight : renderData.pNolit
        glUseProgram(prog)
        glUniform3fv(glGetUniformLocation(prog, "baseColor"), 1, renderData.color)
        glUniformMatrix4fv(glGetUniformLocation(prog, "mvp"), 1, GL_FALSE, mvp)
        glBindVertexArray(renderData.VAO)
        glDrawArrays(GL_TRIANGLES, 0, app.model.vertexCount)
        glBindVertexArray(0)
        glUseProgram(0)

        renderUI(app, renderData)
        GLFW.PollEvents()
        GLFW.SwapBuffers(app.window)
        begin
            app.configs.imguiFocus = CImGui.IsWindowFocused(CImGui.ImGuiFocusedFlags_AnyWindow)
            app.camera.ratio = app.configs.winW / convert(Float32, app.configs.winH)
            framerate = convert(Float32, CImGui.GetIO().Framerate)
            delta = !iszero(framerate) ? app.camera.sensMove / framerate * 100.0f0 : app.camera.sensMove
            deltaFront = delta * app.configs.keyDown[1] - delta * app.configs.keyDown[3]
            deltaRight = delta * app.configs.keyDown[4] - delta * app.configs.keyDown[2]
            processKey!(app.camera, delta * deltaFront, delta * deltaRight)
        end
    end
end

function renderUI(app, renderData)
    if !app.configs.showUI
        return
    end
    CImGui.ImGui_ImplOpenGL3_NewFrame()
    CImGui.ImGui_ImplGlfw_NewFrame()
    CImGui.NewFrame()
    flags = 0
    flags |= CImGui.ImGuiWindowFlags_NoTitleBar
    p_open = true
    @c CImGui.Begin("UI", &p_open, flags)
    if CImGui.BeginTabBar(APPNAME)
        if CImGui.BeginTabItem("System")
            CImGui.Text(@sprintf("Application: %s", APPNAME))
            CImGui.Text(@sprintf("Window Size: (%dx%d)", app.configs.winW, app.configs.winH))
            CImGui.Text(@sprintf("FPS: %.2f", CImGui.GetIO().Framerate))
            CImGui.Separator()
            @c CImGui.Checkbox("Wireframe", &app.configs.wireframe)
            if @c CImGui.Checkbox("OpenGL Debug", &app.configs.gldebug)
                if app.configs.gldebug
                    glEnable(GL_DEBUG_OUTPUT)
                    glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS)
                    glDebugMessageCallback(glDebugCallbackC, C_NULL)
                    glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DONT_CARE, C_NULL, C_NULL, GL_TRUE)
                    glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DEBUG_SEVERITY_NOTIFICATION, C_NULL, C_NULL, false)
                else
                    glDisable(GL_DEBUG_OUTPUT)
                    glDisable(GL_DEBUG_OUTPUT_SYNCHRONOUS)
                    glDebugMessageCallback(C_NULL, C_NULL)
                end
            end
            CImGui.ColorEdit3("Background", app.configs.background)
            CImGui.Separator()
            CImGui.Text("Press F12 to toggle UI")
            CImGui.Text("Author: teamclouday")
            CImGui.EndTabItem()
        end
        if CImGui.BeginTabItem("Camera")
            cam = app.camera
            if CImGui.DragFloat3("Position", cam.p_pos, 0.001f0)
                updateCamera!(cam)
            end
            if CImGui.DragFloat3("Center", cam.p_center, 0.001f0)
                updateCamera!(cam)
            end
            @c CImGui.Checkbox("Lock Center", &cam.lockCenter)
            CImGui.SameLine()
            if CImGui.Button("Center To Origin")
                cam.p_center = [0f0,0f0,0f0]
                updateCamera!(cam)
            end
            CImGui.SetNextTreeNodeOpen(false, CImGui.ImGuiCond_FirstUseEver)
            if CImGui.CollapsingHeader("View")
                @c CImGui.DragFloat("Fov", &cam.fov, 0.1f0, 0.1f0, 180.0f0, "%.1f")
                @c CImGui.DragFloat("Near", &cam.near, 0.001f0, 0.001f0, 10.0f0, "%.3f")
                @c CImGui.DragFloat("Far", &cam.far, 0.1f0, 10.0f0, 10000.0f0, "%.1f")
            end
            CImGui.SetNextTreeNodeOpen(false, CImGui.ImGuiCond_FirstUseEver)
            if CImGui.CollapsingHeader("Sensitivity")
                @c CImGui.DragFloat("Rotate", &cam.sensTurn, 0.001f0, 0.001f0, 1.0f0, "%.3f")
                @c CImGui.DragFloat("Move", &cam.sensMove, 0.001f0, 0.001f0, 1.0f0, "%.3f")
            end
            if CImGui.CollapsingHeader("Additional Info")
                CImGui.Text(@sprintf("Front: (%.2f, %.2f, %.2f)", cam.p_front.x, cam.p_front.y, cam.p_front.z))
                CImGui.Text(@sprintf("Up: (%.2f, %.2f, %.2f)", cam.p_up.x, cam.p_up.y, cam.p_up.z))
                CImGui.Text(@sprintf("Right: (%.2f, %.2f, %.2f)", cam.p_right.x, cam.p_right.y, cam.p_right.z))
                CImGui.Text(@sprintf("Distance: %.4f", cam.dist))
            end
            CImGui.EndTabItem()
        end
        if CImGui.BeginTabItem("Model")
            CImGui.ColorEdit3("Color", renderData.color)
            CImGui.DragFloat3("Translation", renderData.tTrans, 0.001f0)
            @c CImGui.DragFloat("Rotation", &renderData.tRotScale.x, 0.1f0, -360.0f0, 360.0f0, "%.1f")
            @c CImGui.DragFloat("Scale", &renderData.tRotScale.y, 0.001f0, 0.001f0)
            @c CImGui.Checkbox("Enable Light", &renderData.enableLight)
            CImGui.EndTabItem()
        end
        CImGui.EndTabBar()
    end
    CImGui.End()
    CImGui.Render()
    CImGui.ImGui_ImplOpenGL3_RenderDrawData(CImGui.GetDrawData())
end

function initApp(model)
    # initialize context
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
    GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 3)
    GLFW.WindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE)
    # create window
    window = GLFW.CreateWindow(APPWIDTH, APPHEIGHT, APPNAME)
    @assert window != C_NULL "Failed to create GLFW window!"
    GLFW.MakeContextCurrent(window)
    GLFW.SwapInterval(1)
    # setup OpenGL
    glEnable(GL_DEPTH_TEST)
    glEnable(GL_CULL_FACE)
    glCullFace(GL_BACK)
    glFrontFace(GL_CCW)
    # initialize ImGui
    imgui = CImGui.CreateContext()
    @assert imgui != C_NULL "Failed to create ImGui context!"
    CImGui.StyleColorsDark()
    CImGui.ImGui_ImplGlfw_InitForOpenGL(window, true)
    CImGui.ImGui_ImplOpenGL3_Init(130)
    # camera
    camera = Camera(pos=Vector3{Float32}(0,4,4), center=Vector3{Float32}(0,0,0))
    updateCamera!(camera)
    # create app
    app = Application(window, imgui, camera, model, Configs())
    # set callbacks
    GLFW.SetKeyCallback(window, (_, key, scancode, action, mods) -> begin
        if action == GLFW.PRESS
            if key == GLFW.KEY_ESCAPE
                GLFW.SetWindowShouldClose(app.window, true)
            elseif key == GLFW.KEY_F12
                app.configs.showUI = !app.configs.showUI
            end
        end
        if key == GLFW.KEY_W
            app.configs.keyDown[1] = action != GLFW.RELEASE
        elseif key == GLFW.KEY_A
            app.configs.keyDown[2] = action != GLFW.RELEASE
        elseif key == GLFW.KEY_S
            app.configs.keyDown[3] = action != GLFW.RELEASE
        elseif key == GLFW.KEY_D
            app.configs.keyDown[4] = action != GLFW.RELEASE
        end
    end)
    GLFW.SetCursorPosCallback(window, (_, posX, posY) -> begin
        pos = app.configs.mousePos
        if pos[1] < 0.0
            pos[1] = pos[3] = posX
            pos[2] = pos[4] = posY
        else
            pos[1], pos[2] = pos[3], pos[4]
            pos[3], pos[4] = posX, posY
            processMouse!(app.camera,
                convert(Float32, pos[1]-pos[3]),
                convert(Float32, pos[2]-pos[4]),
                app.configs.mouseDown[1],
                app.configs.mouseDown[2])
        end
    end)
    GLFW.SetMouseButtonCallback(window, (_, button, action, mods) -> begin
        mouseDown = app.configs.mouseDown
        if button == GLFW.MOUSE_BUTTON_LEFT
            mouseDown[1] = action == GLFW.PRESS
        elseif button == GLFW.MOUSE_BUTTON_RIGHT
            mouseDown[2] = action == GLFW.PRESS
        end
        if app.configs.imguiFocus
            mouseDown[1] = mouseDown[2] = false
        end
        if !mouseDown[1] && !mouseDown[2]
            app.configs.mousePos[1] = -1.0
        end
    end)
    GLFW.SetScrollCallback(window, (_, xoffset, yoffset) -> begin
        if !app.configs.imguiFocus
            processWheel!(app.camera, convert(Float32, -yoffset))
        end
    end)
    return app
end

function destroyApp(app)
    CImGui.ImGui_ImplOpenGL3_Shutdown()
    CImGui.ImGui_ImplGlfw_Shutdown()
    CImGui.DestroyContext(app.imgui)
    GLFW.DestroyWindow(app.window)
    GLFW.Terminate()
end

function loadRenderData(app)
    model = computeModelRenderData(app.model)
    # load shaders
    shaders = [
        createShader(joinpath("shaders", "nolit.vert.glsl"), GL_VERTEX_SHADER, true),
        createShader(joinpath("shaders", "nolit.frag.glsl"), GL_FRAGMENT_SHADER, true),
        createShader(joinpath("shaders", "light.vert.glsl"), GL_VERTEX_SHADER, true),
        createShader(joinpath("shaders", "light.frag.glsl"), GL_FRAGMENT_SHADER, true)
    ]
    pNolit = createShaderProgram(shaders[1:2])
    pLight = createShaderProgram(shaders[3:4])
    # prepare VAO, VBO, EBO
    VAO::GLuint = 0
    @c glGenVertexArrays(1, &VAO)
    glBindVertexArray(VAO)
    VBO::GLuint = 0
    @c glGenBuffers(1, &VBO)
    glBindBuffer(GL_ARRAY_BUFFER, VBO)
    glBufferData(GL_ARRAY_BUFFER, sizeof(Float32) * length(model.vertices), model.vertices, GL_STATIC_DRAW)
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(Float32), Ptr{Cvoid}(0))
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 6 * sizeof(Float32), Ptr{Cvoid}(3 * sizeof(Float32)))
    glEnableVertexAttribArray(0)
    glEnableVertexAttribArray(1)
    glBindVertexArray(0)
    return RenderData(
        VAO, VBO, pNolit, pLight, Color3{Float32}(1,1,1),
        Vector3{Float32}(0,0,0), Vector2{Float32}(0,1), true
    )
end

main()