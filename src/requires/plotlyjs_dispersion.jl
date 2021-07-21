using .PlotlyJS
import .PlotlyJS: plot
                                          # from https://flatuicolors.com/palette/gb
const BAND_COL  = Ref("rgb(39,60,117)")   # "mazarine blue"
const KLINE_COL = Ref("rgb(220,221,225)") # "hint of pensive"

const DEFAULT_PLOTLY_LAYOUT_DISPERSION = Layout(
    showlegend=false,
    xaxis=attr(zeroline=false,
            showgrid=true, showbackground=false,
            gridcolor = KLINE_COL[], ticks="outside",
            showline=true, mirror=true, # show axis boundary
            ),
    yaxis=attr(zeroline=false,
            showgrid=false, showbackground=false,
            ticks="outside",
            showline=true, mirror="all", # show axis boundaries on all subplots
            ),
    hovermode = "closest",
    autosize = true,
    width = 480, height = 480,
    #margin=attr(l=50, r=5, b=15, t=10),

    plot_bgcolor="rgba(255, 255, 255, 1)", paper_bgcolor="rgba(255, 255, 255, 1)",
    )

"""
    plot(kpi::KPathInterpolant, bands, [layout]; kwargs...)

Plot a dispersion diagram for provided `bands` and **k**-path interpolant `kpi`.

`bands` must be an iterable of iterables of `<:Real`s (e.g., a `Vector{Vector{Float64}}`),
with the first iteration running over distinct energy bands, and the second running
over distinct **k**-points in `kpi`.
Note that the length of each iterant of `bands` must equal `length(kpi)`.

Alternatively, `bands` can be an `AbstractMatrix{<:Real}`, with columns interpreted as
distinct energy bands and rows as distinct **k**-points.

## Keyword arguments `kwargs`

- `ylims`: y-axis limits (default: quasi-tight around `bands`'s range)

- `ylabel`: y-axis label (default: "Energy")

- `title`: plot title (default: `nothing`); can be a `String` or an `attr` dictionary of
  PlotlyJS properties

- `band_highlights`: dictionary of non-default styling for specified band ranges (default:
  `nothing`, indicating all-default styling).

  **Example**: To color bands 2 and 3 black, set
  `band_highlights = Dict(2:3 => attr(color=:black, width=3)`.
  Unlisted band ranges are shown in default band styling.

- `annotations`: dictionary of hover-text annotations for labeled high-symmetry points in
  `kpi` (default: `nothing`, indicating no annotations). Suitable for labeling of irreps.

  **Example**: Assume bands 1 and 2 touch at :X, but not at :Γ. To label this, we set:
  `annotations = Dict(:X => [1:2 => "touching!], :Γ => [1 => "isolated", 2 => "isolated"])`.
  If a band-range is provided, a single annotation is placed at the mean of the energies
  at these band-ranges.
"""
function plot(kpi::KPathInterpolant, bands,
              layout::Layout = DEFAULT_PLOTLY_LAYOUT_DISPERSION;
              ylims = nothing, ylabel = "Energy", title = nothing,
              band_highlights::Union{Dict, Nothing} = nothing,
              annotations::Union{Dict, Nothing} = nothing)
    # check input
    N = length(kpi)
    if !all(band -> length(band) == N, bands)
        throw(DimensionMismatch("mismatched dimensions of `kpi` and `bands`"))
    end
    # copy layout since we may want to mutate the layout and don't want to corrupt it
    layout = deepcopy(layout)

    # set default y-limits in layout, if not already set
    haskey(layout, :yaxis) || (layout[:yaxis] = attr())
    if isnothing(ylims)
        if !haskey(layout[:yaxis], :range)
            ylims = default_dispersion_ylims(bands)
            layout[:yaxis][:range] = ylims
        else
            ylims = layout[:yaxis][:range] # grab what was already in `layout`
        end
    else
        # overwrite if ylims was provided, regardless of what it is in `layout`
        layout[:yaxis][:range] = ylims
    end
    layout[:yaxis][:title] = ylabel

    # add title, if requested
    if !isnothing(title)
        if title isa String
            layout[:title] = attr(text=title)
        else
            layout[:title] = title
        end
    end

    # prepare to plot band diagram
    Npaths           = length(kpi.kpaths)
    local_xs         = cumdists.(kpi.kpaths)
    local_xs_lengths = last.(local_xs)
    total_xs_lengths = sum(local_xs_lengths)
    spacing          = total_xs_lengths / 30
    rel_xs_lengths   = local_xs_lengths./(total_xs_lengths+spacing*(Npaths-1))
    rel_spacing      = spacing/(total_xs_lengths+spacing*(Npaths-1))

    # plot bands and k-lines/labels
    tbands = Vector{GenericTrace{Dict{Symbol,Any}}}()
    xticks = [Vector{Float64}(undef, length(labels)) for labels in kpi.labels]
    xlabs  = [Vector{Symbol}(undef, length(labels)) for labels in kpi.labels]
    start_idx = 1
    domain_start = 0.0 # subplot domain "start" point
    for (path_idx, (local_x, labels)) in enumerate(zip(local_xs, kpi.labels))
        stop_idx = start_idx+length(local_x)-1
        # plot bands
        for (i, band) in enumerate(bands)
            line = something(_get_value_if_in_ranges(band_highlights, i), 
                             attr(color=BAND_COL[], width=3)) # default            
            push!(tbands,
                PlotlyJS.scatter(x=local_x, y=band[start_idx:stop_idx],
                    hoverinfo="y", mode="lines", line=line, xaxis="x$path_idx", yaxis="y"))
        end
        # define xticks
        for (lab_idx, (x_idx, lab)) in enumerate(labels)
            xticks[path_idx][lab_idx] = local_x[x_idx]
            xlabs[path_idx][lab_idx]  = lab
        end
        # place any high-symmetry point annotations
        if annotations !== nothing
            for (lab, bandidxs_and_strs) in annotations
                for idx in findall(==(Symbol(lab)), labels)
                    for (bandidxs, str) in bandidxs_and_strs
                        Nbandidxs = length(bandidxs)
                        freq = sum(b->bands[b][idx + start_idx - 1], bandidxs)/Nbandidxs
                        push!(tbands,
                                PlotlyJS.scatter(x = local_x[idx:idx], y=freq:freq,
                                    hoverinfo="text", hovertext=str, mode="marker",
                                    line=attr(color=:black), xaxis="x$path_idx", yaxis="y"))
                    end
                end
            end
        end
        
        # set subplot sizes and local xticks & xrange
        sym_xaxis = Symbol("xaxis$path_idx") # subplot xaxis name

        layout[sym_xaxis] = copy(get(layout, :xaxis, attr()))
        layout[sym_xaxis][:range]  = [extrema(local_x)...]
        layout[sym_xaxis][:tickvals] = xticks[path_idx]
        layout[sym_xaxis][:ticktext] = xlabs[path_idx]
        
        domain_end = domain_start + rel_xs_lengths[path_idx]
        layout[Symbol(sym_xaxis, "_domain")] = [domain_start, domain_end]
        domain_start = domain_end + rel_spacing

        # prepare for next iteration
        start_idx = stop_idx + 1
    end
    delete!(layout.fields, :xaxis) # get rid of unused xaxis in layout; causes artifacts...

    return plot(tbands, layout)
end
# `bands` can also be supplied as a matrix (w/ distinct bands in distinct columns)
function plot(kpi::KPathInterpolant, bands::AbstractMatrix{<:Real},
    layout::Layout = DEFAULT_PLOTLY_LAYOUT_DISPERSION; kwargs...)
    # TODO: would be nice to avoid collecting `eachcol` here, but if we don't, then we run
    #       into problems with not being able to index into `eachcol(bands)` since it's a
    #       generator... problem is gone if https://github.com/JuliaLang/julia/pull/32310
    #       or https://github.com/JuliaLang/julia/pull/37648 are merged
    plot(kpi, collect(eachcol(bands)), layout; kwargs...)
end

function default_dispersion_ylims(bands)
    ylims = [mapfoldl(minimum, min, bands, init=Inf), 
             mapfoldl(maximum, max, bands, init=-Inf)]
    δ = (ylims[2]-ylims[1])/30
    if isapprox(ylims[1], 0, atol=1e-6)
        ylims[2] += δ
    else
        ylims .+= (-δ, δ)
    end
    return ylims
end

function _get_value_if_in_ranges(d::Dict, i::Integer)
    for (k, v) in d
        i ∈ k && return v
    end
    return nothing
end
_get_value_if_in_ranges(::Nothing, ::Integer) = nothing