module Renderer
using GLFW, ModernGL
using CImGui
using Printf

export RendererData
export CreateRenderer, DestroyRenderer, RenderLoop

mutable struct RendererData
    window
    imgui
    imguiUI
    camera
    model
end

const APPNAME   = "AccelerateRT"
const APPWIDTH  = 800
const APPHEIGHT = 600

function CreateRenderer()
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
    # create renderer
    renderer = RendererData(window, imgui, true, 0, 0)
    # set key callback
    GLFW.SetKeyCallback(window, (_, key, scancode, action, mods) -> begin  
        if action == GLFW.PRESS
            if key == GLFW.KEY_ESCAPE
                GLFW.SetWindowShouldClose(renderer.window, true)
            elseif key == GLFW.KEY_F12
                renderer.imguiUI = !renderer.imguiUI
            end
        end
    end)
    return renderer
end

function DestroyRenderer(renderer::RendererData)
    CImGui.ImGui_ImplOpenGL3_Shutdown()
    CImGui.ImGui_ImplGlfw_Shutdown()
    CImGui.DestroyContext(renderer.imgui)
    GLFW.DestroyWindow(renderer.window)
    GLFW.Terminate()
end

function RenderUI(renderer::RendererData)
    if !renderer.imguiUI
        return
    end
    CImGui.ImGui_ImplOpenGL3_NewFrame()
    CImGui.ImGui_ImplGlfw_NewFrame()
    CImGui.NewFrame()

    flags = 0
    flags |= CImGui.ImGuiWindowFlags_NoTitleBar

    p_open = Ref{Bool}(true)

    CImGui.Begin("UI", p_open, flags)

    if CImGui.BeginTabBar(APPNAME)
        if CImGui.BeginTabItem("System")
            CImGui.Text(@sprintf("Application: %s", APPNAME))
            winW, winH = GLFW.GetFramebufferSize(renderer.window)
            CImGui.Text(@sprintf("Window Size: (%dx%d)", winW, winH))
            CImGui.Text(@sprintf("FPS: %.2f", CImGui.GetIO().Framerate))
            CImGui.Text("Author: teamclouday")
            CImGui.EndTabItem()
        end
        CImGui.EndTabBar()
    end

    CImGui.End()
    CImGui.Render()
    CImGui.ImGui_ImplOpenGL3_RenderDrawData(CImGui.GetDrawData())
end

function ProcessInput(renderer::RendererData)
    if GLFW.GetKey(renderer.window, GLFW.KEY_ESCAPE)
        GLFW.SetWindowShouldClose(renderer.window, true)
    end
end

function RenderLoop(renderer::RendererData)
    while !GLFW.WindowShouldClose(renderer.window)
        winW, winH = GLFW.GetFramebufferSize(renderer.window)
        glViewport(0, 0, winW, winH)
        glClearColor(0.2, 0.2, 0.2, 1.0)
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
        # Render here

        # UI
        RenderUI(renderer)
        GLFW.SwapBuffers(renderer.window)
        GLFW.PollEvents()
        ProcessInput(renderer)
    end
end

end