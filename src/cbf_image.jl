# Load in the image part of a CBF file, ignoring all else
import Base.Libc:FILE

# libcbf routines that we need
#
# libcbf expects the address of a cbf_handle_struct *
# typedefed to cbf_handle. The address doesn't have
# to point to an actual cbf_handle_struct but must
# be something that libcbf can update.

mutable struct CBF_Handle_Struct end

mutable struct CBF_Handle
    handle::Ptr{CBF_Handle_Struct}
end

cbf_make_handle() = begin
    handle = CBF_Handle(0)
    finalizer(cbf_free_handle!,handle)
    err_no = ccall((:cbf_make_handle,"libcbf"),Cint,(Ref{CBF_Handle},),handle)
    cbf_error(err_no)
    #println("Our handle is $(handle.handle)")
    return handle
end

cbf_free_handle!(handle::CBF_Handle) = begin
    q = time_ns()
    #error_string = "$q: Finalizing CBF Handle $(handle.handle)"
    #t = @task println(error_string)
    #schedule(t)
    err_no = ccall((:cbf_free_handle,"libcbf"),Cint,(Ptr{CBF_Handle_Struct},),handle.handle)
    cbf_error(err_no, extra = "while finalising")
    return 0
end

cbf_read_file(filename) = begin
    handle = cbf_make_handle()
    f = open(filename,"r")
    fptr = Base.Libc.FILE(f)
    flags = 0
    #println("Our file pointer is $fptr")
    err_no = ccall((:cbf_read_file,"libcbf"),Cint,(Ptr{CBF_Handle_Struct},FILE,Cint),handle.handle,fptr,flags)
    cbf_error(err_no, extra = "while trying to read $filename")
    return handle
end

cbf_get_arraysize(handle) = begin
    compression = Ref{Cuint}(0)
    bid =  Ref{Cint}(0)
    elsize = Ref{Csize_t}(0)
    elsigned = Ref{Cint}(0)
    elunsigned = Ref{Cint}(0)
    elements = Ref{Csize_t}(0)
    minelem = Ref{Cint}(0)
    maxelem = Ref{Cint}(0)
    isreal = Ref{Cint}(0)
    byteorder = Ref{Ptr{UInt8}}(0)
    fast = Ref{Csize_t}(0)
    mid = Ref{Csize_t}(0)
    slow = Ref{Csize_t}(0)
    padding = Ref{Csize_t}(0)
    err_no = ccall((:cbf_get_arrayparameters_wdims,"libcbf"),Cint,
              (Ptr{CBF_Handle_Struct},
               Ref{Cuint}, #compression
               Ref{Cint}, #binary_id
               Ref{Csize_t}, #elsize
               Ref{Cint},
               Ref{Cint},
               Ref{Csize_t}, #elements
               Ref{Cint},
               Ref{Cint},
               Ref{Cint}, #is real
               Ref{Ptr{UInt8}}, #byteorder
               Ref{Csize_t}, #fast
               Ref{Csize_t}, #mid
               Ref{Csize_t}, #slow
               Ref{Csize_t}, #padding
               )
              , handle.handle,compression, bid, elsize,elsigned,elunsigned,
              elements,minelem, maxelem, isreal, byteorder,fast,mid,slow,padding)
    cbf_error(err_no, extra = "while trying to get array size")
    #println("Compression type $(compression[]) for binary id $(bid[])")
    #println("elements = $(elements[]) of size $(elsize[])")
    #println("Dims $(fast[]) x $(mid[]) x $(slow[])")
    #println("Is real? $(isreal[])")
    bo = @GC.preserve unsafe_string(byteorder[])
    #println("Check: byte order is $bo")
    if isreal[] != 0    # real numbers
        if elsize[] == 4
            elt = Float32
        elseif elsize[] == 8
            elt = Float64
        else
            throw(error("No real type with size $(elsize[])"))
        end
    else   # integers
        if elsize[] == 4
            elt = Int32
        elseif elsize[] == 8
            elt = Int64
        elseif elsize[] == 2
            elt = Int16
        else throw(error("No integer type with size $(elsize[])"))
        end
    end
    return elements[],elt,fast[],mid[],slow[]
end

cbf_get_realarray(handle,data_array) = begin
    bid = Ref{Cint}(0)
    num_read = Ref{Csize_t}(0)
    fast,mid = size(data_array)
    elsize = sizeof(eltype(data_array))
    err_no = ccall((:cbf_get_realarray,"libcbf"),Cint,
                   (Ptr{CBF_Handle_Struct},
                    Ref{Cint}, #binary id
                    Ptr{Float64},
                    Csize_t,
                    Csize_t,
                    Ref{Csize_t}
                    ),handle.handle,bid,data_array,elsize,fast*mid,num_read)
    cbf_error(err_no, extra = "while reading in array")
    #println("Read in $(num_read[]) values")
    return num_read[]
end

cbf_get_integerarray(handle,data_array) = begin
    bid = Ref{Cint}(0)
    num_read = Ref{Csize_t}(0)
    fast,mid = size(data_array)
    elt = eltype(data_array)
    elsize = sizeof(elt)
    is_signed = Ref{Cint}(signed(elt) == elt ? 1 : 0)
    err_no = ccall((:cbf_get_integerarray,"libcbf"),Cint,
                   (Ptr{CBF_Handle_Struct},
                    Ref{Cint}, #binary id
                    Ptr{Float64},
                    Csize_t,
                    Ref{Cint},
                    Csize_t,
                    Ref{Csize_t}
                    ),handle.handle,bid,data_array,elsize,is_signed,fast*mid,num_read)
    cbf_error(err_no, extra = "while reading in array")
    #println("Read in $(num_read[]) values")
    return num_read[]
end

"""
    imgload(filename,::Val{:CBF})

Return a single image from `filename`, which should be in (mini)CBF format and contain a single
frame.
"""
imgload(filename::AbstractString,::Val{:CBF};path=nothing,frame=nothing) = begin
    handle = cbf_read_file(filename)
    err_no = ccall((:cbf_find_category,"libcbf"),Cint,(Ptr{CBF_Handle_Struct},Cstring),handle.handle,"array_data")
    cbf_error(err_no, extra = "while searching for array_data")
    err_no = ccall((:cbf_find_column,"libcbf"),Cint,(Ptr{CBF_Handle_Struct},Cstring),handle.handle,"data")
    cbf_error(err_no, extra = "while searching for data column")
    err_no = ccall((:cbf_rewind_row,"libcbf"),Cint,(Ptr{CBF_Handle_Struct},),handle.handle)
    cbf_error(err_no)
    # Find the dimensions of the array
    total_size,elt,fast,mid,slow = cbf_get_arraysize(handle)
    # Create an array for this information
    data_array = Array{elt,2}(undef,fast,mid)
    if elt <: AbstractFloat
        num_read = cbf_get_realarray(handle,data_array)
    else
        num_read = cbf_get_integerarray(handle,data_array)
    end
    if num_read != total_size
        throw(error("Read failure: expected $total_size, read $num_read"))
    end
    return data_array
end

cbf_error(val;extra="") = begin
    if val == 0 return end
    throw(error("CBF Error: $(cbf_error_dict[val]) $extra"))
    # TODO: actually do an AND for multiple errors
end

const cbf_error_dict = Dict(
          0 => :CBF_SUCCESS        ,
 0x00000001 => :CBF_FORMAT         , 
 0x00000002 => :CBF_ALLOC          , 
 0x00000004 => :CBF_ARGUMENT       , 
 0x00000008 => :CBF_ASCII          , 
 0x00000010 => :CBF_BINARY         , 
 0x00000020 => :CBF_BITCOUNT        ,
 0x00000040 => :CBF_ENDOFDATA       ,
 0x00000080 => :CBF_FILECLOSE       ,
 0x00000100 => :CBF_FILEOPEN        ,
 0x00000200 => :CBF_FILEREAD        ,
 0x00000400 => :CBF_FILESEEK        ,
 0x00000800 => :CBF_FILETELL        ,
 0x00001000 => :CBF_FILEWRITE       ,
 0x00002000 => :CBF_IDENTICAL       ,
 0x00004000 => :CBF_NOTFOUND        ,
 0x00008000 => :CBF_OVERFLOW        ,
 0x00010000 => :CBF_UNDEFINED       ,
 0x00020000 => :CBF_NOTIMPLEMENTED  ,
 0x00040000 => :CBF_NOCOMPRESSION   ,  
 0x00080000 => :CBF_H5ERROR         ,
 0x00100000 => :CBF_H5DIFFERENT     ,
 0x00200000 => :CBF_SIZE            )
