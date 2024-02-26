# Based on code from M. Bauman Stackexchange answer + Gitter discussion

"""
```julia
VectorOfArray(u::AbstractVector)
```

A `VectorOfArray` is an array which has the underlying data structure `Vector{AbstractArray{T}}`
(but, hopefully, concretely typed!). This wrapper over such data structures allows one to lazily
act like it's a higher-dimensional vector, and easily convert it to different forms. The indexing
structure is:

```julia
A.u[i] # Returns the ith array in the vector of arrays
A[j, i] # Returns the jth component in the ith array
A[j1, ..., jN, i] # Returns the (j1,...,jN) component of the ith array
```

which presents itself as a column-major matrix with the columns being the arrays from the vector.
The `AbstractArray` interface is implemented, giving access to `copy`, `push`, `append!`, etc. functions,
which act appropriately. Points to note are:

  - The length is the number of vectors, or `length(A.u)` where `u` is the vector of arrays.
  - Iteration follows the linear index and goes over the vectors

Additionally, the `convert(Array,VA::AbstractVectorOfArray)` function is provided, which transforms
the `VectorOfArray` into a matrix/tensor. Also, `vecarr_to_vectors(VA::AbstractVectorOfArray)`
returns a vector of the series for each component, that is, `A[i,:]` for each `i`.
A plot recipe is provided, which plots the `A[i,:]` series.

There is also support for `VectorOfArray` with constructed from multi-dimensional arrays

```julia
VectorOfArray(u::AbstractArray{AT}) where {T, N, AT <: AbstractArray{T, N}}
```

where `IndexStyle(typeof(u)) isa IndexLinear`.
"""
mutable struct VectorOfArray{T, N, A} <: AbstractVectorOfArray{T, N, A}
    u::A # A <: AbstractVector{<: AbstractArray{T, N - 1}}
end
# VectorOfArray with an added series for time

"""
```julia
DiffEqArray(u::AbstractVector, t::AbstractVector)
```

This is a `VectorOfArray`, which stores `A.t` that matches `A.u`. This will plot
`(A.t[i],A[i,:])`. The function `tuples(diffeq_arr)` returns tuples of `(t,u)`.

To construct a DiffEqArray

```julia
t = 0.0:0.1:10.0
f(t) = t - 1
f2(t) = t^2
vals = [[f(tval) f2(tval)] for tval in t]
A = DiffEqArray(vals, t)
A[1, :]  # all time periods for f(t)
A.t
```
"""
mutable struct DiffEqArray{T, N, A, B, F, S} <: AbstractDiffEqArray{T, N, A}
    u::A # A <: AbstractVector{<: AbstractArray{T, N - 1}}
    t::B
    p::F
    sys::S
end
### Abstract Interface
struct AllObserved
end

function Base.Array(VA::AbstractVectorOfArray{
        T,
        N,
        A
}) where {T, N,
        A <: AbstractVector{
            <:AbstractVector,
        }}
    reduce(hcat, VA.u)
end
function Base.Array(VA::AbstractVectorOfArray{
        T,
        N,
        A
}) where {T, N,
        A <:
        AbstractVector{<:Number}}
    VA.u
end
function Base.Matrix(VA::AbstractVectorOfArray{
        T,
        N,
        A
}) where {T, N,
        A <: AbstractVector{
            <:AbstractVector,
        }}
    reduce(hcat, VA.u)
end
function Base.Matrix(VA::AbstractVectorOfArray{
        T,
        N,
        A
}) where {T, N,
        A <:
        AbstractVector{<:Number}}
    Matrix(VA.u)
end
function Base.Vector(VA::AbstractVectorOfArray{
        T,
        N,
        A
}) where {T, N,
        A <: AbstractVector{
            <:AbstractVector,
        }}
    vec(reduce(hcat, VA.u))
end
function Base.Vector(VA::AbstractVectorOfArray{
        T,
        N,
        A
}) where {T, N,
        A <:
        AbstractVector{<:Number}}
    VA.u
end
function Base.Array(VA::AbstractVectorOfArray)
    vecs = vec.(VA.u)
    Array(reshape(reduce(hcat, vecs), size(VA.u[1])..., length(VA.u)))
end
function Base.Array{U}(VA::AbstractVectorOfArray) where {U}
    vecs = vec.(VA.u)
    Array(reshape(reduce(hcat, vecs), size(VA.u[1])..., length(VA.u)))
end
function Adapt.adapt_structure(to, VA::AbstractVectorOfArray)
    Adapt.adapt(to, Array(VA))
end

function VectorOfArray(vec::AbstractVector{T}, ::NTuple{N}) where {T, N}
    VectorOfArray{eltype(T), N, typeof(vec)}(vec)
end
# Assume that the first element is representative of all other elements
function VectorOfArray(vec::AbstractVector)
    T = eltype(vec[1])
    N = ndims(vec[1])
    if all(x isa Union{<:AbstractArray, <:AbstractVectorOfArray} for x in vec)
        A = Vector{Union{typeof.(vec)...}}
    else
        A = typeof(vec)
    end
    VectorOfArray{T, N + 1, A}(vec)
end
function VectorOfArray(vec::AbstractVector{VT}) where {T, N, VT <: AbstractArray{T, N}}
    VectorOfArray{T, N + 1, typeof(vec)}(vec)
end

# allow multi-dimensional arrays as long as they're linearly indexed. 
# currently restricted to arrays whose elements are all the same type
function VectorOfArray(array::AbstractArray{AT}) where {T, N, AT <: AbstractArray{T, N}}
    @assert IndexStyle(typeof(array)) isa IndexLinear

    return VectorOfArray{T, N + 1, typeof(array)}(array)
end

Base.parent(vec::VectorOfArray) = vec.u

function DiffEqArray(vec::AbstractVector{T},
        ts::AbstractVector,
        ::NTuple{N, Int},
        p = nothing,
        sys = nothing) where {T, N}
    DiffEqArray{eltype(T), N, typeof(vec), typeof(ts), typeof(p), typeof(sys)}(vec,
        ts,
        p,
        sys)
end

# ambiguity resolution
function DiffEqArray(vec::AbstractVector{VT},
        ts::AbstractVector,
        ::NTuple{N, Int}) where {T, N, VT <: AbstractArray{T, N}}
    DiffEqArray{eltype(T), N, typeof(vec), typeof(ts), Nothing, Nothing}(vec,
        ts,
        nothing,
        nothing)
end
function DiffEqArray(vec::AbstractVector{VT},
        ts::AbstractVector,
        ::NTuple{N, Int}, p) where {T, N, VT <: AbstractArray{T, N}}
    DiffEqArray{eltype(T), N, typeof(vec), typeof(ts), typeof(p), Nothing}(vec,
        ts,
        p,
        nothing)
end
# Assume that the first element is representative of all other elements

function DiffEqArray(vec::AbstractVector,
        ts::AbstractVector,
        p = nothing,
        sys = nothing;
        variables = nothing,
        parameters = nothing,
        independent_variables = nothing)
    sys = something(sys,
        SymbolCache(something(variables, []),
            something(parameters, []),
            something(independent_variables, [])))
    _size = size(vec[1])
    T = eltype(vec[1])
    return DiffEqArray{
        T,
        length(_size) + 1,
        typeof(vec),
        typeof(ts),
        typeof(p),
        typeof(sys)
    }(vec,
        ts,
        p,
        sys)
end

function DiffEqArray(vec::AbstractVector{VT},
        ts::AbstractVector,
        p = nothing,
        sys = nothing;
        variables = nothing,
        parameters = nothing,
        independent_variables = nothing) where {T, N, VT <: AbstractArray{T, N}}
    sys = something(sys,
        SymbolCache(something(variables, []),
            something(parameters, []),
            something(independent_variables, [])))
    return DiffEqArray{
        eltype(eltype(vec)),
        N + 1,
        typeof(vec),
        typeof(ts),
        typeof(p),
        typeof(sys)
    }(vec,
        ts,
        p,
        sys)
end

SymbolicIndexingInterface.is_timeseries(::Type{<:AbstractVectorOfArray}) = Timeseries()
SymbolicIndexingInterface.state_values(A::AbstractDiffEqArray) = A.u
SymbolicIndexingInterface.current_time(A::AbstractDiffEqArray) = A.t
SymbolicIndexingInterface.parameter_values(A::AbstractDiffEqArray) = A.p
SymbolicIndexingInterface.symbolic_container(A::AbstractDiffEqArray) = A.sys

Base.IndexStyle(A::AbstractVectorOfArray) = Base.IndexStyle(typeof(A))
Base.IndexStyle(::Type{<:AbstractVectorOfArray}) = IndexCartesian()

@inline Base.length(VA::AbstractVectorOfArray) = length(VA.u)
@inline function Base.eachindex(VA::AbstractVectorOfArray)
    return eachindex(VA.u)
end
@inline function Base.eachindex(
        ::IndexLinear, VA::AbstractVectorOfArray{T, N, <:AbstractVector{T}}) where {T, N}
    return eachindex(IndexLinear(), VA.u)
end
@inline Base.IteratorSize(::Type{<:AbstractVectorOfArray}) = Base.HasLength()
@inline Base.first(VA::AbstractVectorOfArray) = first(VA.u)
@inline Base.last(VA::AbstractVectorOfArray) = last(VA.u)
function Base.firstindex(VA::AbstractVectorOfArray)
    Base.depwarn(
        "Linear indexing of `AbstractVectorOfArray` is deprecated. Change `A[i]` to `A.u[i]` ",
        :firstindex)
    return firstindex(VA.u)
end

function Base.lastindex(VA::AbstractVectorOfArray)
    Base.depwarn(
        "Linear indexing of `AbstractVectorOfArray` is deprecated. Change `A[i]` to `A.u[i]` ",
        :lastindex)
    return lastindex(VA.u)
end

@deprecate Base.getindex(A::AbstractVectorOfArray, I::Int) Base.getindex(A, :, I) false

@deprecate Base.getindex(A::AbstractVectorOfArray, I::AbstractArray{Int}) Base.getindex(
    A, :, I) false

@deprecate Base.getindex(A::AbstractDiffEqArray, I::AbstractArray{Int}) Base.getindex(
    A, :, I) false

@deprecate Base.getindex(A::AbstractDiffEqArray, i::Int) Base.getindex(A, :, i) false

__parameterless_type(T) = Base.typename(T).wrapper
Base.@propagate_inbounds function _getindex(A::AbstractVectorOfArray{T, N},
        ::NotSymbolic, I::Colon...) where {T, N}
    @assert length(I) == ndims(A.u[1]) + 1
    vecs = if N == 1
        A.u
    else
        vec.(A.u)
    end
    return Adapt.adapt(__parameterless_type(T),
        reshape(reduce(hcat, vecs), size(A.u[1])..., length(A.u)))
end

Base.@propagate_inbounds function _getindex(A::AbstractVectorOfArray{T, N},
        ::NotSymbolic, I::AbstractArray{Bool},
        J::Colon...) where {T, N}
    @assert length(J) == ndims(A.u[1]) + 1 - ndims(I)
    @assert size(I) == size(A)[1:(ndims(A) - length(J))]
    return A[ntuple(x -> Colon(), ndims(A))...][I, J...]
end

# Need two of each methods to avoid ambiguities
Base.@propagate_inbounds function _getindex(
        A::AbstractVectorOfArray, ::NotSymbolic, ::Colon, I::Int)
    A.u[I]
end

Base.@propagate_inbounds function _getindex(A::AbstractVectorOfArray, ::NotSymbolic,
        I::Union{Int, AbstractArray{Int}, AbstractArray{Bool}, Colon}...)
    if last(I) isa Int
        A.u[last(I)][Base.front(I)...]
    else
        stack(getindex.(A.u[last(I)], tuple.(Base.front(I))...))
    end
end
Base.@propagate_inbounds function _getindex(
        VA::AbstractVectorOfArray, ::NotSymbolic, ii::CartesianIndex)
    ti = Tuple(ii)
    i = last(ti)
    jj = CartesianIndex(Base.front(ti))
    return VA.u[i][jj]
end

Base.@propagate_inbounds function _getindex(
        A::AbstractVectorOfArray, ::NotSymbolic, ::Colon,
        I::Union{AbstractArray{Int}, AbstractArray{Bool}})
    VectorOfArray(A.u[I])
end

Base.@propagate_inbounds function _getindex(A::AbstractDiffEqArray, ::NotSymbolic, ::Colon,
        I::Union{AbstractArray{Int}, AbstractArray{Bool}})
    DiffEqArray(A.u[I], A.t[I], parameter_values(A), symbolic_container(A))
end

# Symbolic Indexing Methods
Base.@propagate_inbounds function _getindex(A::AbstractDiffEqArray, ::ScalarSymbolic, sym)
    if is_independent_variable(A, sym)
        return A.t
    elseif is_variable(A, sym)
        if constant_structure(A)
            return getindex.(A.u, variable_index(A, sym))
        else
            return getindex.(A.u, variable_index.((A,), (sym,), eachindex(A.t)))
        end
    elseif is_parameter(A, sym)
        error("Indexing with parameters is deprecated. Use `getp(A, $sym)` for parameter indexing.")
    elseif is_observed(A, sym)
        return observed(A, sym).(A.u, (parameter_values(A),), A.t)
    else
        # NOTE: this is basically just for LabelledArrays. It's better if this
        # were an error. Should we make an extension for LabelledArrays handling
        # this case?
        return getindex.(A.u, sym)
    end
end

Base.@propagate_inbounds function _getindex(
        A::AbstractDiffEqArray, ::ScalarSymbolic, sym, args...)
    if is_independent_variable(A, sym)
        return A.t[args...]
    elseif is_variable(A, sym)
        return A[sym][args...]
    elseif is_observed(A, sym)
        u = A.u[args...]
        t = A.t[args...]
        observed_fn = observed(A, sym)
        if t isa AbstractArray
            return observed_fn.(u, (parameter_values(A),), t)
        else
            return observed_fn(u, parameter_values(A), t)
        end
    else
        # NOTE: this is basically just for LabelledArrays. It's better if this
        # were an error. Should we make an extension for LabelledArrays handling
        # this case?
        return getindex.(A.u[args...], sym)
    end
end

Base.@propagate_inbounds function _getindex(
        A::AbstractDiffEqArray, ::ArraySymbolic, sym, args...)
    return getindex(A, collect(sym), args...)
end

Base.@propagate_inbounds function _getindex(
        A::AbstractDiffEqArray, ::ScalarSymbolic, sym::Union{Tuple, AbstractArray})
    if all(x -> is_parameter(A, x), sym)
        error("Indexing with parameters is deprecated. Use `getp(A, $sym)` for parameter indexing.")
    else
        return [getindex.((A,), sym, i) for i in eachindex(A.t)]
    end
end

Base.@propagate_inbounds function _getindex(
        A::AbstractDiffEqArray, ::ScalarSymbolic, sym::Union{Tuple, AbstractArray}, args...)
    return reduce(vcat, map(s -> A[s, args...]', sym))
end

Base.@propagate_inbounds function _getindex(A::AbstractDiffEqArray, ::ScalarSymbolic,
        ::SymbolicIndexingInterface.SolvedVariables, args...)
    return getindex(A, variable_symbols(A), args...)
end

Base.@propagate_inbounds function _getindex(A::AbstractDiffEqArray, ::ScalarSymbolic,
        ::SymbolicIndexingInterface.AllVariables, args...)
    return getindex(A, all_variable_symbols(A), args...)
end

Base.@propagate_inbounds function Base.getindex(A::AbstractVectorOfArray, _arg, args...)
    symtype = symbolic_type(_arg)
    elsymtype = symbolic_type(eltype(_arg))

    if symtype != NotSymbolic()
        return _getindex(A, symtype, _arg, args...)
    else
        return _getindex(A, elsymtype, _arg, args...)
    end
end

Base.@propagate_inbounds function Base.getindex(
        A::Adjoint{T, <:AbstractVectorOfArray}, idxs...) where {T}
    return getindex(A.parent, reverse(to_indices(A, idxs))...)
end

function _observed(A::AbstractDiffEqArray{T, N}, sym, i::Int) where {T, N}
    observed(A, sym)(A.u[i], A.p, A.t[i])
end
function _observed(A::AbstractDiffEqArray{T, N}, sym, i::AbstractArray{Int}) where {T, N}
    observed(A, sym).(A.u[i], (A.p,), A.t[i])
end
function _observed(A::AbstractDiffEqArray{T, N}, sym, ::Colon) where {T, N}
    observed(A, sym).(A.u, (A.p,), A.t)
end

Base.@propagate_inbounds function Base.setindex!(VA::AbstractVectorOfArray{T, N}, v,
        ::Colon, I::Int) where {T, N}
    VA.u[I] = v
end

@deprecate Base.setindex!(VA::AbstractVectorOfArray, v, I::Int) Base.setindex!(VA, v, :, I) false

Base.@propagate_inbounds function Base.setindex!(VA::AbstractVectorOfArray{T, N}, v,
        ::Colon, I::Colon) where {T, N}
    VA.u[I] = v
end

@deprecate Base.setindex!(VA::AbstractVectorOfArray, v, I::Colon) Base.setindex!(
    VA, v, :, I) false

Base.@propagate_inbounds function Base.setindex!(VA::AbstractVectorOfArray{T, N}, v,
        ::Colon, I::AbstractArray{Int}) where {T, N}
    VA.u[I] = v
end

@deprecate Base.setindex!(VA::AbstractVectorOfArray, v, I::AbstractArray{Int}) Base.setindex!(
    VA, v, :, I) false

Base.@propagate_inbounds function Base.setindex!(
        VA::AbstractVectorOfArray{T, N}, v, i::Int,
        ::Colon) where {T, N}
    for j in 1:length(VA.u)
        VA.u[j][i] = v[j]
    end
    return v
end
Base.@propagate_inbounds function Base.setindex!(VA::AbstractVectorOfArray{T, N}, x,
        ii::CartesianIndex) where {T, N}
    ti = Tuple(ii)
    i = last(ti)
    jj = CartesianIndex(Base.front(ti))
    return VA.u[i][jj] = x
end

Base.@propagate_inbounds function Base.setindex!(VA::AbstractVectorOfArray{T, N},
        x,
        idxs::Union{Int, Colon, CartesianIndex, AbstractArray{Int}, AbstractArray{Bool}}...) where {
        T, N}
    v = view(VA, idxs...)
    # error message copied from Base by running `ones(3, 3, 3)[:, 2, :] = 2`
    if length(v) != length(x)
        throw(ArgumentError("indexed assignment with a single value to possibly many locations is not supported; perhaps use broadcasting `.=` instead?"))
    end
    for (i, j) in zip(eachindex(v), eachindex(x))
        v[i] = x[j]
    end
    return x
end

# Interface for the two-dimensional indexing, a more standard AbstractArray interface
@inline Base.size(VA::AbstractVectorOfArray) = (size(VA.u[1])..., length(VA.u))
@inline Base.size(VA::AbstractVectorOfArray, i) = size(VA)[i]
@inline Base.size(A::Adjoint{T, <:AbstractVectorOfArray}) where {T} = reverse(size(A.parent))
@inline Base.size(A::Adjoint{T, <:AbstractVectorOfArray}, i) where {T} = size(A)[i]
Base.axes(VA::AbstractVectorOfArray) = Base.OneTo.(size(VA))
Base.axes(VA::AbstractVectorOfArray, d::Int) = Base.OneTo(size(VA)[d])

Base.@propagate_inbounds function Base.setindex!(VA::AbstractVectorOfArray{T, N}, v,
        I::Int...) where {T, N}
    VA.u[I[end]][Base.front(I)...] = v
end

function Base.:(==)(A::AbstractVectorOfArray, B::AbstractVectorOfArray)
    return A.u == B.u
end
function Base.:(==)(A::AbstractVectorOfArray, B::AbstractArray)
    return A.u == B
end
Base.:(==)(A::AbstractArray, B::AbstractVectorOfArray) = B == A

# The iterator will be over the subarrays of the container, not the individual elements
# unlike an true AbstractArray
function Base.iterate(VA::AbstractVectorOfArray, state = 1)
    state >= length(VA.u) + 1 ? nothing : (VA[:, state], state + 1)
end
tuples(VA::DiffEqArray) = tuple.(VA.t, VA.u)

# Growing the array simply adds to the container vector
function _copyfield(VA, fname)
    if fname == :u
        copy(VA.u)
    elseif fname == :t
        copy(VA.t)
    else
        getfield(VA, fname)
    end
end
function Base.copy(VA::AbstractVectorOfArray)
    typeof(VA)((_copyfield(VA, fname) for fname in fieldnames(typeof(VA)))...)
end

function Base.zero(VA::AbstractVectorOfArray)
    val = copy(VA)
    for i in eachindex(VA.u)
        val.u[i] = zero(VA.u[i])
    end
    return val
end

Base.sizehint!(VA::AbstractVectorOfArray{T, N}, i) where {T, N} = sizehint!(VA.u, i)

Base.reverse!(VA::AbstractVectorOfArray) = reverse!(VA.u)
Base.reverse(VA::AbstractVectorOfArray) = VectorOfArray(reverse(VA.u))
function Base.reverse(VA::AbstractDiffEqArray)
    DiffEqArray(reverse(VA.u), VA.t, parameter_values(VA), symbolic_container(VA))
end

function Base.resize!(VA::AbstractVectorOfArray, i::Integer)
    if Base.hasproperty(VA, :sys) && VA.sys !== nothing
        error("resize! is not allowed on AbstractVectorOfArray with a sys")
    end
    Base.resize!(VA.u, i)
    if Base.hasproperty(VA, :t) && VA.t !== nothing
        Base.resize!(VA.t, i)
    end
end

function Base.pointer(VA::AbstractVectorOfArray)
    Base.pointer(VA.u)
end

function Base.push!(VA::AbstractVectorOfArray{T, N}, new_item::AbstractArray) where {T, N}
    push!(VA.u, new_item)
end

function Base.append!(VA::AbstractVectorOfArray{T, N},
        new_item::AbstractVectorOfArray{T, N}) where {T, N}
    for item in copy(new_item)
        push!(VA, item)
    end
    return VA
end

function Base.stack(VA::AbstractVectorOfArray; dims = :)
    stack(stack.(VA.u); dims)
end

# AbstractArray methods
function Base.view(A::AbstractVectorOfArray{T, N, <:AbstractVector{T}},
        I::Vararg{Any, M}) where {T, N, M}
    @inline
    if length(I) == 1
        J = map(i -> Base.unalias(A, i), to_indices(A, I))
    elseif length(I) == 2 && (I[1] == Colon() || I[1] == 1)
        J = map(i -> Base.unalias(A, i), to_indices(A, Base.tail(I)))
    end
    @boundscheck checkbounds(A, J...)
    SubArray(A, J)
end
function Base.view(A::AbstractVectorOfArray, I::Vararg{Any, M}) where {M}
    @inline
    J = map(i -> Base.unalias(A, i), to_indices(A, I))
    @boundscheck checkbounds(A, J...)
    SubArray(A, J)
end
function Base.SubArray(parent::AbstractVectorOfArray, indices::Tuple)
    @inline
    SubArray(IndexStyle(Base.viewindexing(indices), IndexStyle(parent)), parent,
        Base.ensure_indexable(indices), Base.index_dimsum(indices...))
end
Base.isassigned(VA::AbstractVectorOfArray, idxs...) = checkbounds(Bool, VA, idxs...)
function Base.check_parent_index_match(
        ::RecursiveArrayTools.AbstractVectorOfArray{T, N}, ::NTuple{N, Bool}) where {T, N}
    nothing
end
Base.ndims(::AbstractVectorOfArray{T, N}) where {T, N} = N

function Base.checkbounds(
        ::Type{Bool}, VA::AbstractVectorOfArray{T, N, <:AbstractVector{T}},
        idxs...) where {T, N}
    if length(idxs) == 2 && (idxs[1] == Colon() || idxs[1] == 1)
        return checkbounds(Bool, VA.u, idxs[2])
    end
    return checkbounds(Bool, VA.u, idxs...)
end
function Base.checkbounds(::Type{Bool}, VA::AbstractVectorOfArray, idx...)
    checkbounds(Bool, VA.u, last(idx)) || return false
    for i in last(idx)
        checkbounds(Bool, VA.u[i], Base.front(idx)...) || return false
    end
    return true
end
function Base.checkbounds(VA::AbstractVectorOfArray, idx...)
    checkbounds(Bool, VA, idx...) || throw(BoundsError(VA, idx))
end
function Base.copyto!(dest::AbstractVectorOfArray{T, N},
        src::AbstractVectorOfArray{T2, N}) where {T, T2, N}
    for (i, j) in zip(eachindex(dest.u), eachindex(src.u))
        if ArrayInterface.ismutable(dest.u[i]) || dest.u[i] isa AbstractVectorOfArray
            copyto!(dest.u[i], src.u[j])
        else
            dest.u[i] = StaticArraysCore.similar_type(dest.u[i])(src.u[j])
        end
    end
end
function Base.copyto!(
        dest::AbstractVectorOfArray{T, N}, src::AbstractArray{T2, N}) where {T, T2, N}
    for (i, slice) in zip(eachindex(dest.u), eachslice(src, dims = ndims(src)))
        if ArrayInterface.ismutable(dest.u[i]) || dest.u[i] isa AbstractVectorOfArray
            copyto!(dest.u[i], slice)
        else
            dest.u[i] = StaticArraysCore.similar_type(dest.u[i])(slice)
        end
    end
    dest
end
function Base.copyto!(dest::AbstractVectorOfArray{T, N, <:AbstractVector{T}},
        src::AbstractVector{T2}) where {T, T2, N}
    copyto!(dest.u, src)
    dest
end
# Required for broadcasted setindex! when slicing across subarrays
# E.g. if `va = VectorOfArray([rand(3, 3) for i in 1:5])`
# Need this method for `va[2, :, :] .= 3.0`
Base.@propagate_inbounds function Base.maybeview(A::AbstractVectorOfArray, I...)
    return view(A, I...)
end

# Operations
function Base.isapprox(A::AbstractVectorOfArray,
        B::Union{AbstractVectorOfArray, AbstractArray};
        kwargs...)
    return all(isapprox.(A, B; kwargs...))
end

function Base.isapprox(A::AbstractArray, B::AbstractVectorOfArray; kwargs...)
    return all(isapprox.(A, B; kwargs...))
end

for op in [:(Base.:-), :(Base.:+)]
    @eval function ($op)(A::AbstractVectorOfArray, B::AbstractVectorOfArray)
        ($op).(A, B)
    end
    @eval Base.@propagate_inbounds function ($op)(A::AbstractVectorOfArray,
            B::AbstractArray)
        @boundscheck length(A) == length(B)
        VectorOfArray([($op).(a, b) for (a, b) in zip(A, B)])
    end
    @eval Base.@propagate_inbounds function ($op)(
            A::AbstractArray, B::AbstractVectorOfArray)
        @boundscheck length(A) == length(B)
        VectorOfArray([($op).(a, b) for (a, b) in zip(A, B)])
    end
end

for op in [:(Base.:/), :(Base.:\), :(Base.:*)]
    if op !== :(Base.:/)
        @eval ($op)(A::Number, B::AbstractVectorOfArray) = ($op).(A, B)
    end
    if op !== :(Base.:\)
        @eval ($op)(A::AbstractVectorOfArray, B::Number) = ($op).(A, B)
    end
end

function Base.CartesianIndices(VA::AbstractVectorOfArray)
    if !allequal(size.(VA.u))
        error("CartesianIndices only valid for non-ragged arrays")
    end
    return CartesianIndices((size(VA.u[1])..., length(VA.u)))
end

# Tools for creating similar objects
Base.eltype(::Type{<:AbstractVectorOfArray{T}}) where {T} = T
# TODO: Is there a better way to do this?
@inline function Base.similar(VA::AbstractVectorOfArray, args...)
    if args[end] isa Type
        return Base.similar(eltype(VA)[], args..., size(VA))
    else
        return Base.similar(eltype(VA)[], args...)
    end
end
@inline function Base.similar(VA::VectorOfArray, ::Type{T} = eltype(VA)) where {T}
    VectorOfArray([similar(VA[:, i], T) for i in eachindex(VA.u)])
end

# for VectorOfArray with multi-dimensional parent arrays of arrays where all elements are the same type
function Base.similar(vec::VectorOfArray{
        T, N, AT}) where {T, N, AT <: AbstractArray{<:AbstractArray{T}}}
    return VectorOfArray(similar(Base.parent(vec)))
end

# special-case when the multi-dimensional parent array is just an AbstractVector (call the old method)
function Base.similar(vec::VectorOfArray{
        T, N, AT}) where {T, N, AT <: AbstractVector{<:AbstractArray{T}}}
    return Base.similar(vec, eltype(vec))
end

# fill!
# For DiffEqArray it ignores ts and fills only u
function Base.fill!(VA::AbstractVectorOfArray, x)
    for i in 1:length(VA.u)
        if VA[:, i] isa AbstractArray
            fill!(VA[:, i], x)
        else
            VA[:, i] = x
        end
    end
    return VA
end

Base.reshape(A::AbstractVectorOfArray, dims...) = Base.reshape(Array(A), dims...)

# Need this for ODE_DEFAULT_UNSTABLE_CHECK from DiffEqBase to work properly
@inline Base.any(f, VA::AbstractVectorOfArray) = any(any(f, u) for u in VA.u)
@inline Base.all(f, VA::AbstractVectorOfArray) = all(all(f, u) for u in VA.u)

# conversion tools
vecarr_to_vectors(VA::AbstractVectorOfArray) = [VA[i, :] for i in eachindex(VA.u[1])]
Base.vec(VA::AbstractVectorOfArray) = vec(convert(Array, VA)) # Allocates
# stack non-ragged arrays to convert them
function Base.convert(::Type{Array}, VA::AbstractVectorOfArray)
    if !allequal(size.(VA.u))
        error("Can only convert non-ragged VectorOfArray to Array")
    end
    return Array(VA)
end

# statistics
@inline Base.sum(VA::AbstractVectorOfArray; kwargs...) = sum(identity, VA; kwargs...)
@inline function Base.sum(f, VA::AbstractVectorOfArray; kwargs...)
    mapreduce(f, Base.add_sum, VA; kwargs...)
end
@inline Base.prod(VA::AbstractVectorOfArray; kwargs...) = prod(identity, VA; kwargs...)
@inline function Base.prod(f, VA::AbstractVectorOfArray; kwargs...)
    mapreduce(f, Base.mul_prod, VA; kwargs...)
end

@inline Statistics.mean(VA::AbstractVectorOfArray; kwargs...) = mean(Array(VA); kwargs...)
@inline function Statistics.median(VA::AbstractVectorOfArray; kwargs...)
    median(Array(VA); kwargs...)
end
@inline Statistics.std(VA::AbstractVectorOfArray; kwargs...) = std(Array(VA); kwargs...)
@inline Statistics.var(VA::AbstractVectorOfArray; kwargs...) = var(Array(VA); kwargs...)
@inline Statistics.cov(VA::AbstractVectorOfArray; kwargs...) = cov(Array(VA); kwargs...)
@inline Statistics.cor(VA::AbstractVectorOfArray; kwargs...) = cor(Array(VA); kwargs...)
@inline Base.adjoint(VA::AbstractVectorOfArray) = Adjoint(VA)

# make it show just like its data
function Base.show(io::IO, m::MIME"text/plain", x::AbstractVectorOfArray)
    (println(io, summary(x), ':'); show(io, m, x.u))
end
function Base.summary(A::AbstractVectorOfArray{T, N}) where {T, N}
    string("VectorOfArray{", T, ",", N, "}")
end

function Base.show(io::IO, m::MIME"text/plain", x::AbstractDiffEqArray)
    (print(io, "t: "); show(io, m, x.t); println(io); print(io, "u: "); show(io, m, x.u))
end

# plot recipes
@recipe function f(VA::AbstractVectorOfArray)
    convert(Array, VA)
end
@recipe function f(VA::AbstractDiffEqArray)
    xguide --> isempty(independent_variable_symbols(VA)) ? "" :
    independent_variable_symbols(VA)[1]
    label --> isempty(variable_symbols(VA)) ? "" :
    reshape(string.(variable_symbols(VA)), 1, :)
    VA.t, VA'
end
@recipe function f(VA::DiffEqArray{T, 1}) where {T}
    VA.t, VA.u
end

Base.map(f, A::RecursiveArrayTools.AbstractVectorOfArray) = map(f, A.u)

function Base.mapreduce(f, op, A::AbstractVectorOfArray; kwargs...)
    mapreduce(f, op, view(A, ntuple(_ -> :, ndims(A))...); kwargs...)
end
function Base.mapreduce(
        f, op, A::AbstractVectorOfArray{T, 1, <:AbstractVector{T}}; kwargs...) where {T}
    mapreduce(f, op, A.u; kwargs...)
end

## broadcasting

struct VectorOfArrayStyle{N} <: Broadcast.AbstractArrayStyle{N} end # N is only used when voa sees other abstract arrays
VectorOfArrayStyle(::Val{N}) where {N} = VectorOfArrayStyle{N}()

# The order is important here. We want to override Base.Broadcast.DefaultArrayStyle to return another Base.Broadcast.DefaultArrayStyle.
Broadcast.BroadcastStyle(a::VectorOfArrayStyle, ::Base.Broadcast.DefaultArrayStyle{0}) = a
function Broadcast.BroadcastStyle(::VectorOfArrayStyle{N},
        a::Base.Broadcast.DefaultArrayStyle{M}) where {M, N}
    Base.Broadcast.DefaultArrayStyle(Val(max(M, N)))
end
function Broadcast.BroadcastStyle(::VectorOfArrayStyle{N},
        a::Base.Broadcast.AbstractArrayStyle{M}) where {M, N}
    typeof(a)(Val(max(M, N)))
end
function Broadcast.BroadcastStyle(::VectorOfArrayStyle{M},
        ::VectorOfArrayStyle{N}) where {M, N}
    VectorOfArrayStyle(Val(max(M, N)))
end
function Broadcast.BroadcastStyle(::Type{<:AbstractVectorOfArray{T, N}}) where {T, N}
    VectorOfArrayStyle{N}()
end
# make vectorofarrays broadcastable so they aren't collected
Broadcast.broadcastable(x::AbstractVectorOfArray) = x

@inline function Base.copy(bc::Broadcast.Broadcasted{<:VectorOfArrayStyle})
    bc = Broadcast.flatten(bc)
    N = narrays(bc)
    VectorOfArray(map(1:N) do i
        copy(unpack_voa(bc, i))
    end)
end

for (type, N_expr) in [
    (Broadcast.Broadcasted{<:VectorOfArrayStyle}, :(narrays(bc))),
    (Broadcast.Broadcasted{<:Broadcast.DefaultArrayStyle}, :(length(dest.u)))
]
    @eval @inline function Base.copyto!(dest::AbstractVectorOfArray,
            bc::$type)
        bc = Broadcast.flatten(bc)
        N = $N_expr
        @inbounds for i in 1:N
            if dest[:, i] isa AbstractArray
                if ArrayInterface.ismutable(dest[:, i])
                    copyto!(dest[:, i], unpack_voa(bc, i))
                else
                    unpacked = unpack_voa(bc, i)
                    arr_type = StaticArraysCore.similar_type(dest[:, i])
                    dest[:, i] = if length(unpacked) == 1
                        fill(copy(unpacked), arr_type)
                    else
                        arr_type(unpacked[j] for j in eachindex(unpacked))
                    end
                end
            else
                dest[:, i] = copy(unpack_voa(bc, i))
            end
        end
        dest
    end
end

## broadcasting utils

"""
    narrays(A...)

Retrieve number of arrays in the AbstractVectorOfArrays of a broadcast.
"""
narrays(A) = 0
narrays(A::AbstractVectorOfArray) = length(A.u)
narrays(bc::Broadcast.Broadcasted) = _narrays(bc.args)
narrays(A, Bs...) = common_length(narrays(A), _narrays(Bs))

function common_length(a, b)
    a == 0 ? b :
    (b == 0 ? a :
     (a == b ? a :
      throw(DimensionMismatch("number of arrays must be equal"))))
end

_narrays(args::AbstractVectorOfArray) = length(args.u)
@inline _narrays(args::Tuple) = common_length(narrays(args[1]), _narrays(Base.tail(args)))
_narrays(args::Tuple{Any}) = _narrays(args[1])
_narrays(::Any) = 0

# drop axes because it is easier to recompute
@inline function unpack_voa(bc::Broadcast.Broadcasted{Style}, i) where {Style}
    Broadcast.Broadcasted{Style}(bc.f, unpack_args_voa(i, bc.args))
end
@inline function unpack_voa(bc::Broadcast.Broadcasted{<:VectorOfArrayStyle}, i)
    Broadcast.Broadcasted(bc.f, unpack_args_voa(i, bc.args))
end
unpack_voa(x, ::Any) = x
unpack_voa(x::AbstractVectorOfArray, i) = x.u[i]
function unpack_voa(x::AbstractArray{T, N}, i) where {T, N}
    @view x[ntuple(x -> Colon(), N - 1)..., i]
end

@inline function unpack_args_voa(i, args::Tuple)
    (unpack_voa(args[1], i), unpack_args_voa(i, Base.tail(args))...)
end
unpack_args_voa(i, args::Tuple{Any}) = (unpack_voa(args[1], i),)
unpack_args_voa(::Any, args::Tuple{}) = ()
