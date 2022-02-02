# Provide methods for accessing imgCIF data

#==

# Background

imgCIF is a text format for describing raw data images collected on
crystallographic instruments. As such it is not suited for actually
containing the raw data, but instead provides tags pointing to the
data storage location.

This library provides methods for bringing that image data into
Julia, including handling the variety of formats provided.

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

export imgload         #Load raw data

"""
A CIFImage
"""
abstract type CIFImage end

# Particular formats should subclass `CIFImage` and implement the
#`get_image` method
"""
    get_image(c::CIFImage, frame, path)

Return raw data for frame `frame` found at internal path `path`
"""
get_image(c::CIFImage, frame, path)

#include("hdf_image.jl")
#include("cbf_image.jl")
#include("bruker_image.jl")
#include("adsc_image.jl")

get_image_ids(c::CifBlock) = begin
    return c["_array_data.id"]
end

imgload(location,id) = begin
    
end

"""
    imgload(c::CifBlock,array_id)

Return the image corresponding to the specified raw array identifier.
"""
imgload(c::CifBlock,frame_id) = begin
    ext_loop = get_loop(c,"_array_data.id")
    if !("external_format" in names(ext_loop))
        throw(error("$(c.original_file) does not contain external data pointers"))
    end
    if !("$id" in c["_array_data.id"])
        throw(error("Data with id $id is not found"))
    end
    info = filter(row -> row.id == "$frame_id", ext_loop,view=true)
    if nrow(info) > 1
        throw(error("Array data $frame_id is ambiguous"))
    end
    if nrow(info) == 0
        throw(error("No array data with id $frame_id found"))
    end
    info = info[1,!]
    imgload(info.external_location_uri,
            info.external_path,
            info.external_format,
            info.external_archive_format,
            info.external_archive_path,
            info.external_frame)
end

"""
    imgload(uri,path,format,compressed,arch_path,frame::Int)

Return the raw 2D data found at `uri`, optionally compressed into
an archive of format `compressed` with internal archive path to the data
of `arch_path`. The object thus referenced has `format` and the target
frame is `frame`.
"""
imgload(uri,path,format,compressed,arch_path,frame::Union{Int,Nothing}) = begin
    # Set up input stream
    stream = IOBuffer()
    if compressed != nothing
        if compressed == "TGZ"
            decomp = GzipDecompressor()
        elseif compressed == "TBZ"
            decomp = BzipDecompressor()
        end
        stream = TranscodingStream(decomp,stream)
    end
    # Now handle having an internal directory structure
    if arch_path != nothing
        if compressed in ("TGZ","TBZ")
            loc = Tar.extract(x->x.path==arch_path,stream)
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
    end
    stream = Downloads.download(uri,stream;verbose=true)
    seekstart(stream)
    count = write(final_file,read(stream))
    println("$count bytes read")
    close(final_file)
    #
    println("Extracted file to $loc")
    if format == "HDF5"
        f = h5open(loc)
        if !ismissing(frame) && !isnothing(frame)
            return f[path][frame]
        else
            return read(f[path])
        end
    elseif format == "CBF"  #one frame per file
        return cbfload(loc)
    else
        raise(error("$format Not implemented"))
    end
end

imgload(c::CifBlock,frame::Int;scan=nothing,diffrn=nothing) = begin
    
    println("Not implemented yet")
end

imgload(p::AbstractPath,id) = begin
    c = first(CifFile(p)).second
    imgload(c,id)
end

frame_from_frame_id(c::CifBlock,frame::String,scan,diffrn) = begin
    # The frame number is provided in _diffrn_scan_frame.frame_number
    
end

end  #of module
