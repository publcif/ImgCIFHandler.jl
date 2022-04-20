#
#  Auto-install all required items
#
import Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using ImgCIFHandler
using ImageInTerminal, Colors,ImageContrastAdjustment
using ArgParse
using CrystalInfoFramework,FilePaths,URIs, Tar

# Tests for imgCIF files
const test_list = []
const test_list_with_img = []
const test_full_list = []

# These macros will become more sophisticated
# with time to make a nice printout. For now
# they simply collect the tests into three
# lists.
macro noimgcheck(description, check)
    # extract name
    #func_name = expr.args[1].args[1] #:=->:call
    #push!(test_list,func_name)
    quote
        x = $(esc(check))
        push!(test_list,($(esc(description)),x))
    end
end

macro imgcheck(description, check)
    quote
        x = $(esc(check))
        push!(test_list_with_img,($(esc(description)),x))
    end
end

macro fullcheck(description, check)
    quote
        x = $(esc(check))
        push!(test_full_list,($(esc(description)), x))
    end
end

#macro plaincheck(testname,testexpr,message)
#end

# Checks that do not require an image

@noimgcheck "Required items" required_items(incif) = begin
    messages = []
    info_check = ("_array_structure_list.dimension",
                  "_array_structure_list.index",
                  "_array_structure_list.precedence",
                  "_array_structure_list.direction",
                  "_array_structure_list_axis.displacement_increment",
                  "_array_structure_list_axis.displacement",
                  "_diffrn_scan_axis.axis_id",
                  "_diffrn_scan_axis.angle_start",
                  "_diffrn_scan_axis.displacement_start",
                  "_diffrn_scan_axis.angle_range",
                  "_diffrn_scan_axis.displacement_range",
                  "_diffrn_scan_axis.angle_increment",
                  "_diffrn_scan.frames",
                  "_axis.depends_on",
                  "_axis.type",
                  "_axis.vector[1]",
                  "_axis.vector[2]",
                  "_axis.vector[3]",
                  "_axis.offset[1]",
                  "_axis.offset[2]",
                  "_axis.offset[3]",
                  "_diffrn_radiation_wavelength.id",
                  "_diffrn_radiation_wavelength.value",
                  "_diffrn_radiation.type",
                  "_array_data.array_id",
                  "_array_data.binary_id")
    for ic in info_check
        if !haskey(incif,ic)
            push!(messages,(false,"Required item $ic is missing"))
        end
    end
    return messages
end

# Make sure there is a data specification
@noimgcheck "Data source" data_source(incif) = begin
    messages = []
    if !haskey(incif,"_array_data.data") && !haskey(incif,"_array_data.external_format") && !haskey(incif,"_array_data.external_path")
        push!(messages,(false,"No source of image data specified"))
    end
    if haskey(incif,"_array_data.data")
        push!(messages,(true,"WARNING:raw data included in file, processing will be slow"))
    end
    p = URI(incif["_array_data.external_location_uri"][1])
    if p.scheme == "file" || p.scheme == nothing
        push!(messages,(true,"WARNING: external data stored in local file system, this is not portable"))
    end
    if resolvereference("file:///dummy",p) != p
        push!(messages,(true,"WARNING: relative URI $p provided, this is not portable"))
    end
    return messages
end

@noimgcheck "Axes defined" axes_defined(incif) = begin
    all_axes = vcat(incif["_axis.id"],[nothing])
    messages = []
    test_values = ("_axis.depends_on","_diffrn_scan_frame_axis.axis_id",
                   "_diffrn_scan_axis.axis_id",
                   "_diffrn_measurement_axis.axis_id",
                   "_diffrn_detector_axis.axis_id",
                   "_array_structure_list_axis.axis_id")
    for tv in test_values
        if !haskey(incif,tv) continue end
        unk = setdiff(skipmissing(incif[tv]),all_axes)
        if length(unk) > 0
            push!(messages,(false,"Undefined axes in $tv: $unk"))
        end
    end
    return messages
end

@noimgcheck "Our limitations" our_limitations(incif) = begin
    messages = []
    if length(unique(incif["_array_data.array_id"])) > 1
        push!(messages,(false,"WARNING: cannot currently correctly check files with more than one data array structure"))
    end
    if haskey(incif,"_diffrn_detector.id") && length(unique(incif["_diffrn_detector.id"])) > 1
        push!(messages,(false,"WARNING: cannot currently correctly check files with more than one detector"))
    end
    if haskey(incif,"_diffrn_detector_element.id") && length(unique(incif["_diffrn_detector_element.id"])) > 1
        push!(messages(false,"WARNING: cannot currently correctly check files with more than one detector element"))
    end
    return messages
end

# Check that the detector translation is as expected
@noimgcheck "Detector translation" trans_is_neg(incif) = begin
    messages = []
    # find the detector translation based on the idea that it will
    # be a translation axis directly dependent on 2 theta
    axes = get_loop(incif,"_axis.id")
    tt = filter(axes) do r
        getproperty(r,"_axis.equipment")==    "detector" && getproperty(r,"_axis.type")==     "rotation" &&  getproperty(r,"_axis.depends_on")==nothing
    end
    if size(tt,1) != 1
        return [(true,"Warning: can't identify two theta axis $tt")]
    end
    axname = getproperty(tt,"_axis.id")[]
    det = filter(axes) do r
            getproperty(r,"_axis.equipment") == "detector" && getproperty(r,"_axis.type") == "translation" && getproperty(r,"_axis.depends_on") == axname
    end
    if size(det,1) != 1
        detnames = getproperty(det,"_axis.id")
        return [(true,"Warning: can't identify detector translation axis, have $detnames")]
    end
    det = first(det)
    detname = getproperty(det,"_axis.id")
    # check that translation is negative Z
    signv = sign(parse(Float64,getproperty(det,"_axis.vector[3]")))
    signo = signv*parse(Float64,getproperty(det,"_axis.offset[3]"))
    if signo == 1
        push!(messages,(false,"Detector translation $detname is positive"))
    end
    if signv == 1
        push!(messages,(false,"Detector translation axis $detname points towards the source"))
    end
    av1 = parse(Float64,getproperty(det,"_axis.vector[1]"))
    av2 = parse(Float64,getproperty(det,"_axis.vector[2]"))
    if av1 != 0 || av2 != 0
        push!(messages,(false,"Detector translation is not parallel to beam"))
    end
    return messages
end

# Check that the image is described correctly
# We assume a single array structure for all data
const img_types = Dict(UInt8 =>"unsigned 8-bit integer",
                       UInt16=>"unsigned 16-bit integer",
                       UInt32=>"unsigned 32-bit integer",
                       Int8  =>"signed 8-bit integer",
                       Int16 =>"signed 16-bit integer",
                       Int32 =>"signed 32-bit integer",
                       Float32 =>"signed 32-bit real IEEE",
                       Float64 =>"signed 64-bit real IEEE",
                       ComplexF32 =>"signed 32-bit complex IEEE"
                       )

@imgcheck "Image type and dimensions" img_dims(incif,img,img_id) = begin
    messages = []
    fast_pixels = size(img)[1]
    slow_pixels = size(img)[2]
    fast_pos,slow_pos = indexin(["1","2"],incif["_array_structure_list.precedence"])
    dims = parse.(Int32,incif["_array_structure_list.dimension"])
    if dims[fast_pos] != fast_pixels
        push!(messages,(false,"Stated fast dimension $fast_pos does not match actual image dimension $fast_pixels"))
    end
    if dims[slow_pos] != slow_pixels
        push!(messages,(false,"Stated slow dimension $slow_pos does not match actual image dimension $slow_pixels"))
    end
    if haskey(incif,"_array_structure.encoding_type") && img_types[eltype(img)] != incif["_array_structure.encoding_type"][1]
        push!(messages,(false,"Stated encoding $(incif["_array_structure.encoding_type"][1]) does not match array element type $(eltype(img))"))
    end
    if haskey(incif,"_array_structure.byte_order") && haskey(incif,"_array_data.external_format")
        push!(messages,(true,"WARNING: byte order provided in file containing external data pointers"))
    end
    if haskey(incif,"_array_structure.compression") && incif["_array_structure.compression"][1] != "none" && haskey(incif,"_array_data.external_format")
        push!(messages,(true,"Externally-provided data by definition is uncompressed but compression is specified as $(incif["array_structure.compression"][1])"))
    end
    return messages
end

#######################################################################################
#
#             Check the full archive
#
#######################################################################################
"""
    Download all archives listed in `incif`, returning a dictionary {url -> local file}.
    If `get_full` is false, just start the download and abort as soon as a file is found.
    `subs` is a dictionary of local file equivalents to urls.
"""
download_archives(incif;get_full=false,pick=1,subs=Dict()) = begin
    urls = unique(incif["_array_data.external_location_uri"])
    if !isempty(subs)
        for u in urls
            if !(u in keys(subs))
                throw(error("No local file substitution found for $u; have $(keys(subs)) only"))
            end
        end
        if get_full return subs end
    end
    result_dict = Dict{String,String}()
    for u in urls
        if !isempty(subs)
            loc = URI("file://"*subs[u])
        else
            loc = URI(make_absolute_uri(incif,u))
        end
        pos = indexin([u],incif["_array_data.external_location_uri"])[]
        arch_type = nothing
        if haskey(incif,"_array_data.external_compression")
            arch_type = incif["_array_data.external_compression"][pos]
        end
        x = ""
        if !get_full && arch_type in ("TBZ","TGZ","TAR")
            try
                x = peek_image(loc,arch_type,incif,check_name=false,entry_no=pick)
            catch exn
                @debug "Peeking into $u gave error:" exn
            end
            @debug "Got $x for $u"
            result_dict[u] = x == nothing ? "" : x
        elseif get_full
            result_dict[u] = Downloads.download(u)
        else
            @warn "Partial downloading not available for $u: try full downloading with option -f"
        end
    end
    return result_dict     
end

test_archive_present(local_archives) = begin
    messages = []
    for (k,v) in local_archives
        if v == ""
            push!(messages, (false, "Unable to access $k"))
        end
    end
    return messages
end

@fullcheck "All members present" member_check(incif,all_archives) = begin
    messages = []
end

##############
#
#   Utility routines
#
##############

"""
    Find an image ID that is available in the archive. `archive_list` is
    a dictionary of URI -> item pairs where `item` is an archive member
    if have_full is false, or else it is an entire archive otherwise. 
"""
find_load_id(incif,archive_list,have_full) = begin

    known_paths = incif["_array_data.external_archive_path"]
    
    # First see if our frame is in the file

    if !have_full
        @debug archive_list
        for (k,v) in archive_list
            if v in known_paths
                pos = indexin([v],known_paths)[]
                return incif["_array_data.binary_id"][pos]
            end
        end

        throw(error("Sample image not found, try full archive (option -f)"))
    end

    # Get a list of all archive members
    
end

verdict(msg_list) = begin
    ok = reduce((x,y)-> x[1] & y[1],msg_list;init=true)
    println(ok ? "PASS" : "FAIL")
    for (isok,message) in msg_list
        println("   "*message)
    end
    return ok
end

"""
Display an image in the terminal
"""
display_check_image(im;logscale=true,cut_ratio=1000) = begin
    #alg = Equalization(nbins=256,maxval = floor(maximum(im)/10))
    if maximum(im) > 1.0
        im = im/maximum(im)
    end
    clamp_low,clamp_high = find_best_cutoff(im,cut_ratio=cut_ratio)
    alg = LinearStretching(src_maxval = clamp_high)
    im_new = adjust_histogram(im,alg)
    println("Image for checking")
    #println("Max, min for adjusted image: $(maximum(im_new)), $(minimum(im_new))\n")
    imshow(Gray.(im_new))
    println("\n")
    return im_new
end

"""
Find the best value for displaying a diffraction image, calculated as the first
intensity bin that has 1000 times less points than the highest. Based on the
logic that the highest value will be a "typical" background point. Skip any
that correspond to negative values as these are likely to have a different
meaning.
"""
find_best_cutoff(im;cut_ratio=1000) = begin
    edges,bins = build_histogram(im)
    # Find largest number of points > 0
    maxpts = 0
    maxpos = 0
    for i in 1:length(bins)
        if first(edges) + (i-1)*step(edges) < 0 continue end
        if bins[i] > maxpts
            maxpts = bins[i]
            maxpos = i
        end
        if bins[i] < maxpts break end
    end
    cutoff = maxpts/cut_ratio
    maxbin = maxpos
    for i in maxpos+1:length(bins)
        if bins[i] < cutoff
            maxbin = i
            break
        end
    end
    maxval = first(edges) + maxbin*step(edges)
    minval = first(edges) + maxpos*step(edges)
    #println("Min,max $minval($maxpos),$maxval($maxbin)")
    return minval,maxval
end

#==

     End of routines for individual checks

==#

run_img_checks(incif;images=false,always=false,full=false,connected=false,pick=1,subs=Dict()) = begin
    ok = true
    println("Running checks (no image download)")
    println("="^40*"\n")
    for (desc,one_test) in test_list
        print("\nTesting: $desc: ")
        ok = ok & verdict(one_test(incif))
    end
    testimage = [[]]  # for consistency

    if !connected return (ok, testimage) end
    
    # Test archive access

    println("Testing presence of archive:")
    
    all_archives = download_archives(incif;get_full=full,pick=pick,subs=subs)

    print("\nTesting: All archives are accessible: ")
    
    ok = ok & verdict(test_archive_present(all_archives))
    
    # Test with an image
    
    if length(test_list_with_img) > 0 && ((ok && images) || always)
        testimage = [[]]
        println("\nRunning checks with downloaded images")
        println("="^40*"\n")

        # Choose image to load

        load_id = find_load_id(incif,all_archives,full)
        
        try
            if full
                testimage = imgload(incif,load_id;local_version=all_archives)
            else
                testimage = imgload(incif,load_id;local_version=subs)
            end
        catch e
            verdict([(false,"Unable to access image $load_id: $e")])
            rethrow()
        end
        display_check_image(testimage,logscale=false)
        for (desc,one_test) in test_list_with_img
            print("\nTesting image $load_id: $desc: ")
            ok = ok & verdict(one_test(incif,testimage,load_id))
        end
    end
    
    # Tests requiring fully-downloaded archives

    if full
        for (desc,one_test) in test_full_list
            print("\nTesting full archive: $desc:")
            ok = ok & verdict(one_test(incif,all_archives))
        end
    end
    return (ok,testimage)
end

parse_cmdline(d) = begin
    s = ArgParseSettings(d)
    @add_arg_table! s begin
        "-i", "--check-images"
        help = "Also perform checks on the images"
        nargs = 0
        "-j", "--always-check-images"
        help = "Check images even if non-image checks fail"
        nargs = 0
        "-f", "--full-download"
        help = "Fully download archive for image and archive checks (required for ZIP)"
        nargs = 0
        "-n", "--no-internet"
        help = "Do not check raw image archive existence or contents"
        nargs = 0
        "-p", "--pick"
        nargs = 1
        default = [1]
        arg_type = Int64
        help = "Use this entry number in the archive for checking"
        "-s", "--sub"
        nargs = 2
        metavar = ["original","local"]
        action = "append_arg"
        help = "Use <local> file in place of URI <original> (for testing). Use -f to access whole file. All URIs in <filename> must be provided, option may be used multiple times"
        "filename"
        help = "Name of imgCIF data file to check"
        required = true
        "blockname"
        help = "Block name to check. If missing, the first block is checked"
        required = false
    end
    parse_args(s)
end

if abspath(PROGRAM_FILE) == @__FILE__
    parsed_args = parse_cmdline("Check contents of imgCIF files")
    #println("$parsed_args")
    incif = Cif(Path(parsed_args["filename"]))
    if isnothing(parsed_args["blockname"])
        blockname = first(incif).first
    else
        blockname = parsed_args["blockname"]
    end
    subs = Dict(parsed_args["sub"])
    println("\n ImgCIF checker version 0.2\n")
    println("Checking block $blockname in $(incif.original_file)\n")
    result,img = run_img_checks(incif[blockname],
                                images=parsed_args["check-images"],
                                always=parsed_args["always-check-images"],
                                full = parsed_args["full-download"],
                                connected = !parsed_args["no-internet"],
                                pick = parsed_args["pick"][],
                                subs = subs
                                )
    println("\n====End of Checks====")
    if result exit(0) else exit(1) end
end

    
