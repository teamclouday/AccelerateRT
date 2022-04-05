include("src/renderer.jl")
import .Renderer
import GLFW, ModernGL

renderer = Renderer.CreateRenderer()
Renderer.RenderLoop(renderer)
Renderer.DestroyRenderer(renderer)