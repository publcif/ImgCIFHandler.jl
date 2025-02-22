# Test
using ImgCIFHandler
using Test
using URIs

extract_files() = begin
    # Uncompress archive
    archfile = joinpath(@__DIR__,"testfiles/b4_mini.tar.bz2")
    run(`bunzip2 -k $archfile`)
    # extract files into directory
    detar_dir = joinpath(@__DIR__,"testfiles/test_cbf_unzipped")
    mkpath(detar_dir)
    cd(detar_dir)
    run(`tar -xvf ../b4_mini.tar`)
end

clean_up() = begin
    rm(joinpath(@__DIR__,"testfiles/test_cbf_unzipped"),recursive=true)
    rm(joinpath(@__DIR__,"testfiles/b4_mini.tar"))
end

@testset "Test HDF5 file loading" begin
    q = joinpath(@__DIR__,"testfiles/simple3D.h5")
    x = imgload(q,Val(:HDF),path="/entry/data/test",frame=1)
    @test size(x) == (4,3)
end

@testset "Test ADSC file loading" begin
    q = joinpath(@__DIR__,"testfiles/tartaric_2_003.img")
    x = imgload(q,Val(:SMV))
    @test size(x) == (2048,2048)
end

@testset "Test variants of imgload" begin
    extract_files()
    x = imgload(joinpath(@__DIR__,"testfiles/b4_master.cif"))
    @test size(x) == (4148,4362)
end

@testset "Test CBF file loading" begin
    q = joinpath(@__DIR__,"testfiles/test_cbf_unzipped/s01f0002.cbf")
    x = imgload(q,Val(:CBF))
    @test size(x) == (4148,4362)
end

@testset "Test extraction from archive" begin
    loc = unescapeuri(joinpath(@__DIR__,"testfiles/b4_mini.tar"))
    x = imgload(URI(scheme="file",path=loc),Val(:CBF),arch_type="TAR",arch_path="s01f0003.cbf")
    @test size(x) == (4148,4362)
    loc = unescapeuri(joinpath(@__DIR__,"testfiles/b4_mini.tar.bz2"))
    x = imgload(URI(scheme="file",path=loc),Val(:CBF),arch_type="TBZ",arch_path="s01f0003.cbf")
    @test size(x) == (4148,4362)
end

clean_up()
