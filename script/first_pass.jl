using AMDB
using ByteParsers
using JLD
using RaggedData

import AMDB:
    data_file, all_data_files, data_path, # data paths
    process_file,                         # file processing with parser
    AutoIndex,
    first_pass_streams,
    narrowest_Int, to_narrowest_Int       # narrowing integers

######################################################################
# read whole file -- first pass
######################################################################

# if this part breaks, then column names changed, *rewrite*
cols = AMDB.data_colnames()
@assert cols[1] == "PENR"
@assert cols[6] == "AM"

mutable struct FirstPass{Tid, TAM, TAM_ix, TIO}
    id_counter::RaggedCounter{Tid, Int32}
    AMs::AutoIndex{TAM, TAM_ix} # labor market spells ("Arbeitsmarkt")
    stream_id::TIO
    stream_AM_ix::TIO
    stream_date_start::TIO
    stream_date_stop::TIO
end

# convenience constructor
function FirstPass(parser::Line, base_filename)
    FirstPass(RaggedCounter(Int32, Int32),
              AutoIndex{Vector{UInt8}, Int8}(),
              first_pass_streams(base_filename, "w")...)
end

# dumping dates to files
Base.write(io::IO, date::Date) = unsafe_write(io, Ref(date), sizeof(Date))

function Base.write(io::IO, x::T) where T
    @assert isbits(T) "Can only write bits types."
    unsafe_write(io, Ref(x), sizeof(T))
end

function (fp::FirstPass{Tid, TAM, TAM_ix, TIO})(record) where {Tid,TAM,TAM_ix,TIO}
    id_wide, date_start, date_stop, AM = record
    id = Tid(id_wide)           # conversion to (possibly) narrower type
    push!(fp.id_counter, id)    # record counter
    # save into streams
    write(fp.stream_id, id)
    write(fp.stream_AM_ix, TAM_ix(fp.AMs[AM])) # autoindexing new values
    write(fp.stream_date_start, date_start)
    write(fp.stream_date_stop, date_stop)
end

function Base.close(fp::FirstPass)
    close(fp.stream_id)
    close(fp.stream_AM_ix)
    close(fp.stream_date_start)
    close(fp.stream_date_stop)
end

parser_id_am = Line(PositiveInteger(Int64),
                    DateYYYYMMDD(), DateYYYYMMDD(), Skip(), Skip(),
                    ViewBytes())

fp = FirstPass(parser_id_am, "first_pass")
error_io = open(data_path("first_pass_errors.txt"), "w")
println(error_io, "first pass started at $(Dates.now()) on machine $(gethostname())")
for file in all_data_files()
    println("processing $file")
    err = process_file(file, parser_id_am, fp)
    show(error_io, err)
end
close(error_io)
close(fp)

save(data_path("first_pass_meta.jld"),
     "id_counter", fp.id_counter,
     "AM_keys", keys(fp.AMs))

## run this for testing
fp_meta = load(data_path("first_pass_meta.jld"))
@assert isequal(fp.id_counter.dict, fp_meta["id_counter"].dict)
@assert isequal(fp_meta["AM_keys"], keys(fp.AMs))
