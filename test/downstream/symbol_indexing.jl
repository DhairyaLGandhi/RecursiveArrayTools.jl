using RecursiveArrayTools, ModelingToolkit, OrdinaryDiffEq, SymbolicIndexingInterface, Test
using ModelingToolkit: t_nounits as t, D_nounits as D

include("../testutils.jl")

@variables x(t)
@parameters τ
@variables RHS(t)
@mtkbuild fol_separate = ODESystem([RHS ~ (1 - x) / τ,
        D(x) ~ RHS], t)

prob = ODEProblem(fol_separate, [x => 0.0], (0.0, 10.0), [τ => 3.0])
sol = solve(prob, Tsit5())

sol_new = DiffEqArray(sol.u[1:10],
    sol.t[1:10],
    sol.prob.p,
    sol)

@test sol_new[RHS] ≈ (1 .- sol_new[x]) ./ 3.0
@test sol_new[t] ≈ sol_new.t
@test sol_new[t, 1:5] ≈ sol_new.t[1:5]
@test getp(sol, τ)(sol) == getp(sol_new, τ)(sol_new) == 3.0
@test all(isequal.(variable_symbols(sol), variable_symbols(sol_new)))
@test all(isequal.(variable_symbols(sol), [x]))
@test all(isequal.(all_variable_symbols(sol), all_variable_symbols(sol_new)))
@test all(isequal.(all_variable_symbols(sol), [x, RHS]))
@test all(isequal.(all_symbols(sol), all_symbols(sol_new)))
@test all(isequal.(all_symbols(sol), [x, RHS, τ, t]))
@test sol[solvedvariables] == sol[[x]]
@test sol_new[solvedvariables] == sol_new[[x]]
@test sol[allvariables] == sol[[x, RHS]]
@test sol_new[allvariables] == sol_new[[x, RHS]]
@test_throws Exception sol[τ]
@test_throws Exception sol_new[τ]

# Tables interface
test_tables_interface(sol_new, [:timestamp, Symbol("x(t)")], hcat(sol_new[t], sol_new[x]))

# Two components
@variables y(t)
@parameters α β γ δ
@mtkbuild lv = ODESystem([D(x) ~ α * x - β * x * y,
        D(y) ~ δ * x * y - γ * x * y], t)

prob = ODEProblem(lv, [x => 1.0, y => 1.0], (0.0, 10.0),
    [α => 1.5, β => 1.0, γ => 3.0, δ => 1.0])
sol = solve(prob, Tsit5())

ts = 0:0.5:10
sol_ts = sol(ts)
@assert sol_ts isa DiffEqArray
test_tables_interface(sol_ts, [:timestamp, Symbol("x(t)"), Symbol("y(t)")],
    hcat(ts, Array(sol_ts)'))
