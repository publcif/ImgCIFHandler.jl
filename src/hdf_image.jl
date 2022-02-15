"""
    imgload(handle,::Val{:HDF};path="/";frame=1)

Read a 2D HDF5 image from file `handle` located
at HDF5 location `path`, returning only frame number
`frame`, counting from 1
"""
imgload(loc::AbstractString,::Val{:HDF};path="/",frame=1) = begin
    f = h5open(loc)
    println("Opening HDF5 file at $loc path $path frame $frame")
    if !ismissing(frame) && !isnothing(frame)
        result = f[path][:,:,frame]
    else
        result = read(f[path])
    end
    println("$(size(result))")
    return result
end
