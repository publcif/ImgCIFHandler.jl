# Provide methods for accessing imgCIF data

#==

# Background

imgCIF is a text format for describing raw data images collected on
crystallographic instruments. As such it is not suited for actually
containing the raw data, but instead provides tags pointing to the
data storage location.

This library provides methods for bringing that image data into
Julia, including handling the variety of formats provided. The only
function exported is `imgload`.

==#

module ImgCIFHandler

using CrystalInfoFramework
using FilePaths
import Tar
using CodecBzip2
using CodecZlib
using Downloads
using HDF5
using TranscodingStreams
using URIs

export imgload         #Load raw data

include("hdf_image.jl")
include("cbf_image.jl")
include("adsc_image.jl")

get_image_ids(c::CifContainer) = begin
    return c["_array_data.binary_id"]
end

"""
    imgload(c::Block,array_id)

Return the image referenced in CIF Block `c` corresponding to the specified raw array identifier.
"""
imgload(c::CifContainer,frame_id) = begin
    cat = "_array_data"   #for convenience
    ext_loop = get_loop(c,"$cat.binary_id")
    if !("$cat.external_format" in names(ext_loop))
        throw(error("$(c.original_file) does not contain external data pointers"))
    end
    if !("$frame_id" in c["$cat.binary_id"])
        throw(error("Data with id $frame_id is not found"))
    end
    info = filter(row -> row["$cat.binary_id"] == "$frame_id", ext_loop,view=true)
    if size(info)[1] > 1
        throw(error("Array data $frame_id is ambiguous"))
    end
    if size(info)[1] == 0
        throw(error("No array data with id $frame_id found"))
    end
    info = info[1,:]
    all_cols = names(info)
    full_uri = make_absolute_uri(c,info["$cat.external_location_uri"])
    println("Loading image from $full_uri")
    ext_loc = "$cat.external_location" in all_cols ? info["$cat.external_location"] : nothing
    ext_format = "$cat.external_format" in all_cols ? Val(Symbol(info["$cat.external_format"])) : nothing
    ext_comp = "$cat.external_compression" in all_cols ? info["$cat.external_compression"] : nothing
    ext_ap = "$cat.external_archive_path" in all_cols ? info["$cat.external_archive_path"] : nothing
    ext_frame = "$cat.external_frame" in all_cols ? info["$cat.external_frame"] : nothing
    imgload(full_uri,
            ext_format;
            compressed = ext_comp,
            arch_path = ext_ap,
            path = ext_loc,
            frame = ext_frame
            )
end

"""
    imgload(uri,format;compressed=nothing,arch_path=nothing,path=nothing,frame=1)

Return the raw 2D data found at `uri`, which may have been optionally
compressed into an archive of format `compressed` with internal
archive path to the data of `arch_path`. The object thus referenced
has `format` and the target frame is `frame`.

"""
imgload(uri::URI,format::Val;compressed=nothing,arch_path=nothing,kwargs...)= begin
    # Set up input stream
    stream = IOBuffer()
    # Parse the URI to catch local files
    u = URI(uri)
    stream = Downloads.download("$uri",stream;verbose=true)
    seekstart(stream)
    if !(compressed in (nothing,"TAR"))
        if compressed == "TGZ"
            decomp = GzipDecompressor()
        elseif compressed == "TBZ"
            decomp = Bzip2Decompressor()
        end
        stream = TranscodingStream(decomp,stream)
    end

    # Now handle having an internal directory structure
    if arch_path != nothing
        if compressed in ("TGZ","TBZ","TAR")
            loc = Tar.extract(x->x.path==arch_path,stream)
            loc = joinpath(loc,arch_path)
        elseif compressed == "ZIP"
            w = ZipFile.Reader(stream)
            loc,final_file = mktemp()
            for f in w.files
                if f == arch_path
                    write(final_file,read(f))
                    close(final_file)
                    break
                end
            end
        end
    else
        loc,final_file = mktemp()
        count = write(final_file,read(stream))
        println("$count bytes read")
        close(final_file)
    end
    #
    println("Extracted file to $loc")
    imgload(loc,format;kwargs...)
end

imgload(c::CifContainer,frame::Int;scan=nothing,diffrn=nothing) = begin
    println("Not implemented yet")
end

"""
    imgload(c::CIF)

Return the image referenced by the first encountered `_array_data.binary_id` in the
first block of CIF file `c`.
"""
imgload(c::Cif) = begin
    b = first(c).second
    f_id = b["_array_data.binary_id"][1]
    imgload(b,f_id)
end

imgload(p::AbstractPath) = begin
    imgload(Cif(p))
end

imgload(s::AbstractString) = begin
    imgload(Path(s))
end

frame_from_frame_id(c::CifContainer,frame::String,scan,diffrn) = begin
    # The frame number is provided in _diffrn_scan_frame.frame_number
end

make_absolute_uri(c::CifContainer,u::AbstractString) = begin
    resolvereference(URI(c.original_file),URI(u))
end

end  #of module
