using Test
using FuncDeps

@testset "FuncDeps" begin
    @test isdefined(FuncDeps, :scan_project)
    @test isdefined(FuncDeps, :write_full_dot)
    @test isdefined(FuncDeps, :write_function_focus_dot)
    @test isdefined(FuncDeps, :write_interactive_html)
end
