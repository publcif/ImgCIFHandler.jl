"""
    imgload(handle,::Val{:SMV})

Read an image from an SMV-formatted file
"""
imgload(filename::AbstractString,::Val{:SMV};path=nothing,frame=nothing) = begin
    loc = open(filename,"r")
    header = read_adsc_header(loc)
    seek(loc,parse(Int64,header["header_bytes"]))
    binary = read(loc)  #Sequence of UInt8
    better = reinterpret(UInt16,binary)
    # get the endianness right
    if header["byte_order"]=="little_endian" 
        better = ltoh.(better)
    else
        better = ntoh.(better)
    end
    dim1 = parse(Int64,header["size1"])
    dim2 = parse(Int64,header["size2"])
    data = reshape(better,(dim1,dim2))
    return data
end

read_adsc_header(loc) = begin
    seekstart(loc)
    line = readline(loc)
    header = Dict()
    while !occursin("}",line)
        if occursin("=",line)
            (key,val) = split(String(line),"=")
            header[lowercase(strip(key))] = strip(val,[' ',';','\n','\r']) #an array
        end
        line = readline(loc)
    end
    seekstart(loc)
    return header
end
