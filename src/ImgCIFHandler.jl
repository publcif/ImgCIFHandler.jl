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
using SimpleBufferStream

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
    ext_loc = "$cat.external_path" in all_cols ? info["$cat.external_path"] : nothing
    ext_format = "$cat.external_format" in all_cols ? Val(Symbol(info["$cat.external_format"])) : nothing
    ext_comp = "$cat.external_compression" in all_cols ? info["$cat.external_compression"] : nothing
    ext_ap = "$cat.external_archive_path" in all_cols ? info["$cat.external_archive_path"] : nothing
    ext_frame = "$cat.external_frame" in all_cols ? info["$cat.external_frame"] : nothing
    imgload(full_uri,
            ext_format;
            arch_type = ext_comp,
            arch_path = ext_ap,
            path = ext_loc,
            frame = ext_frame
            )
end

"""
    imgload(uri,format;arch_type=nothing,arch_path=nothing,file_compression=nothing,frame=1)

Return the raw 2D data found at `uri`, which may have been optionally
compressed into an archive of format `compressed` with internal
archive path to the data of `arch_path`. The object thus referenced
has `format` and the target frame is `frame`.

"""
imgload(uri::URI,format::Val;kwargs...) = begin
    # May switch later to native if we can get Tar to terminate early
    imgload_os(uri,format;kwargs...)
end

imgload_os(uri::URI,format::Val;arch_type=nothing,arch_path=nothing,file_compression=nothing,kwargs...) = begin
    # Use OS pipelines to download efficiently
    cmd_list = Cmd[]
    loc = mktempdir()
    decomp_option = "-v"
    if arch_type == "TGZ" decomp_option = "-z" end
    if arch_type == "TBZ" decomp_option = "-j" end
    if arch_type in ("TGZ","TBZ","TAR")
        push!(cmd_list, `curl -s $uri`)
        push!(cmd_list, `tar -C $loc -x $decomp_option -f - --occurrence $arch_path`)
        temp_local = joinpath(loc,arch_path)
    else
        temp_local = joinpath(loc,"temp_download")
        push!(cmd_list, `curl $uri -o $temp_local`)
    end
    #println("Command list is $cmd_list")
    try
        run(pipeline(cmd_list...))
    catch exc
        @debug "Finished downloading" exc
    end
    # Now the final file is in $temp_local
    if arch_type == "ZIP"   #has been downloaded to local storage
        run(`unzip $temp_local $arch_path -d $loc`)
        temp_local = joinpath(loc,arch_path)
    end
    if !isnothing(file_compression)
        final_file = open(joinpath(loc,"final_file"),"w")
        if file_compression == "GZ"
            run(pipeline(`zcat $temp_local`,final_file))
        elseif file_compression == "BZ2"
            run(pipeline(`bzcat $temp_local`,final_file))
        end
        close(final_file)
    else
        mv(temp_local,joinpath(loc,"final_file"))
    end
    imgload(joinpath(loc,"final_file"),format;kwargs...)
end

imgload_native(uri::URI,format::Val;arch_type=nothing,arch_path=nothing,file_compression=nothing,kwargs...)= begin
    # Set up input stream
    stream = BufferStream()
    have_file = false   #changes to true when file found
    loc = mktempdir() #Where the final file is found
    # Parse the URI to catch local files
    u = URI(uri)

    # Begin asynchronous section. Thanks to Julia Discourse for the technique!
    @sync begin
        @async try
            Downloads.download("$uri",stream;verbose=true)
        catch exc
            if !have_file
                @error "Problem downloading $uri" exc
            end
        finally
            close(stream)
        end

        decomp = stream
        if !(arch_type in (nothing,"TAR"))
            if arch_type == "TGZ"
                decomp = GzipDecompressorStream(stream)
            elseif arch_type == "TBZ"
                decomp = Bzip2DecompressorStream(stream)
            end
        end
        # Now handle having an internal directory structure
        if arch_path != nothing
            full_path = joinpath(loc,arch_path)
            if arch_type in ("TGZ","TBZ","TAR")
                # callback to abort after reading
                abort_callback(x) = begin
                    @info("Found: $have_file")
                    if have_file == true
                        if ispath(full_path) && stat(full_path).size > 0
                            @info "$(stat(full_path))"
                            cp(full_path,full_path*"_1")
                            throw(error("Extracted one file to $full_path"))
                        else
                            @info("Can't yet see file at path $full_path or size=0")
                        end     
                    end
                    if x.path == arch_path
                        @info("Extracting", x)
                        have_file = true
                        return true
                    else
                        @info("Ignoring", x)
                        return false
                    end
                end

                @async try
                    Tar.extract(abort_callback,decomp,loc)
                catch exc
                    if !have_file || !ispath(full_path) || isopen(full_path)
                        @info("File at $full_path is $(stat(full_path))")
                        @error "Untar problem" exc
                    end
                finally
                    loc = joinpath(loc,arch_path)
                    close(decomp)
                end
                
            elseif arch_type == "ZIP"
                @async begin
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
            end
        else
            loc,final_file = mktemp()
            @async begin
                count = write(final_file,read(stream))
                println("$count bytes read")
                close(final_file)
            end
        end
    end   #all @asyncs should finish before proceeding
    #
    println("Extracted file to $loc")
    # Apply any final decompression
    endloc = loc
    fdecomp = nothing
    if file_compression == "GZ"
        fdecomp = GzipDecompressor()
    elseif file_compression == "BZ2"
        fdecomp = Bzip2Decompressor()
    end
    if fdecomp != nothing
        endloc,unc_file = mktemp()
        out_str = TranscodingStream(fdecomp,open(loc,"r"))
        write(unc_file,out_str)
        close(unc_file)
        println("Decompressed file is $endloc")
    end
    imgload(endloc,format;kwargs...)
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

## Some utility files

"""
    list_archive(uri;n=5)

Given an archive `uri`, list the first `n` members.
"""
list_archive(u::URI;n=5,compressed=nothing) = begin
    counter = 1
    # Set up input stream
    stream = Pipe()
    # Initialise for blocking input/output
    Base.link_pipe!(stream)  #Not a public API (yet)

    @sync begin
        @async try
            Downloads.download("$u",stream;verbose=true)
        catch exc
            if counter < n
                @error "Problem downloading $uri" exc
            end
        finally
            close(stream)
        end

        decomp = stream
        if !(compressed in (nothing,"TAR"))
            if compressed == "TGZ"
                decomp = GzipDecompressorStream(stream)
            elseif compressed == "TBZ"
                decomp = Bzip2DecompressorStream(stream)
            end
        end
        
        # Now handle having an internal directory structure

        if compressed in ("TGZ","TBZ","TAR")

            # callback to abort after listing

            abort_callback(x) = begin
                counter = counter + 1
                if counter > n
                    throw(error("Made it to $n"))
                end
                @info(x)
                return true
            end

            @async try
                loc = Tar.list(abort_callback,decomp)
            catch exc
                if counter < n
                    @error "Untar problem" exc
                end
            finally
                close(decomp)
            end
        end
    end
end

end  #of module
