# Test HDF5 loading

@testset "Test Single frame HDF5 access" begin
result = imgload("https://zenodo.org/record/3637634/files/WBT0064304.nx.hdf",
                 "/entry1/data/hmm_xy",
                 "HDF5",
                 nothing,
                 nothing,
                 nothing)

println("Dimensions of result are $(size(result)), type is $(typeof(result))")
