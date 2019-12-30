export
    MMTFDict,
    writemmtf

"""
A Macromolecular Transmission Format (MMTF) dictionary.

Can be accessed using similar functions to a standard `Dict`.
Keys are field names as a `String` and values are various types.
To directly access the underlying dictionary of `MMTFDict` `d`, use
`d.dict`.
Call `MMTFDict` with a filepath or stream to read the dictionary from that
source.
The keyword argument `gzip` (default `false`) determines if the file is gzipped.
"""
struct MMTFDict
    dict::Dict{String, Any}
end

# Create an empty MMTF dictionary
# Matches the decoded form of a MMTF file using MMTF.jl
# Encoding and decoding this Dict gives an identical Dict
MMTFDict() = MMTFDict(Dict{String, Any}(
        "altLocList"         => Char[],
        "atomIdList"         => Int32[],
        "bFactorList"        => Float32[],
        "bioAssemblyList"    => Any[],
        "bondAtomList"       => Int32[],
        "bondOrderList"      => Int8[],
        "chainIdList"        => String[],
        "chainNameList"      => String[],
        "chainsPerModel"     => Any[],
        "depositionDate"     => "",
        "entityList"         => Any[],
        "experimentalMethods"=> Any[],
        "groupIdList"        => Int32[],
        "groupList"          => Any[],
        "groupsPerChain"     => Any[],
        "groupTypeList"      => Int32[],
        "insCodeList"        => Char[],
        "mmtfProducer"       => "",
        "mmtfVersion"        => "",
        "ncsOperatorList"    => Any[],
        "numAtoms"           => 0,
        "numBonds"           => 0,
        "numChains"          => 0,
        "numGroups"          => 0,
        "numModels"          => 0,
        "occupancyList"      => Float32[],
        "releaseDate"        => "",
        "resolution"         => 0.0,
        "rFree"              => "",
        "rWork"              => "",
        "secStructList"      => Int8[],
        "sequenceIndexList"  => Int32[],
        "spaceGroup"         => "",
        "structureId"        => "",
        "title"              => "",
        "unitCell"           => Any[],
        "xCoordList"         => Float32[],
        "yCoordList"         => Float32[],
        "zCoordList"         => Float32[]))

MMTFDict(filepath::AbstractString, gzip::Bool=false) = MMTFDict(parsemmtf(filepath; gzip=gzip))
MMTFDict(io::IO, gzip::Bool=false) = MMTFDict(parsemmtf(io; gzip=gzip))

Base.getindex(mmtf_dict::MMTFDict, field::AbstractString) = mmtf_dict.dict[field]

function Base.setindex!(mmtf_dict::MMTFDict,
                    val,
                    field::AbstractString)
    mmtf_dict.dict[field] = val
    return mmtf_dict
end

Base.keys(mmtf_dict::MMTFDict) = keys(mmtf_dict.dict)
Base.values(mmtf_dict::MMTFDict) = values(mmtf_dict.dict)
Base.haskey(mmtf_dict::MMTFDict, key) = haskey(mmtf_dict.dict, key)

function Base.show(io::IO, mmtf_dict::MMTFDict)
    print(io, "MMTF dictionary with $(length(keys(mmtf_dict))) fields")
end


function Base.read(input::IO,
            ::Type{MMTF};
            structure_name::AbstractString="",
            remove_disorder::Bool=false,
            read_std_atoms::Bool=true,
            read_het_atoms::Bool=true,
            gzip::Bool=false)
    d = parsemmtf(input; gzip=gzip)
    struc = ProteinStructure(structure_name)
    # Extract hetero atom information from entity list
    hets = trues(length(d["chainIdList"]))
    for e in d["entityList"]
        if e["type"] == "polymer"
            for i in e["chainIndexList"]
                # 0-based indexing in MMTF
                hets[i + 1] = false
            end
        end
    end
    model_i = 0
    chain_i = 0
    group_i = 0
    atom_i = 0
    for modelchaincount in d["chainsPerModel"]
        model_i += 1
        struc[model_i] = Model(model_i, struc)
        for ci in 1:modelchaincount
            chain_i += 1
            for gi in 1:d["groupsPerChain"][chain_i]
                group_i += 1
                # 0-based indexing in MMTF
                group = d["groupList"][d["groupTypeList"][group_i] + 1]
                for ai in 1:length(group["atomNameList"])
                    atom_i += 1
                    if (read_std_atoms || hets[chain_i]) && (read_het_atoms || !hets[chain_i])
                        unsafe_addatomtomodel!(
                            struc[model_i],
                            AtomRecord(
                                hets[chain_i],
                                d["atomIdList"][atom_i],
                                group["atomNameList"][ai],
                                d["altLocList"][atom_i] == '\0' ? ' ' : d["altLocList"][atom_i],
                                group["groupName"],
                                d["chainNameList"][chain_i],
                                d["groupIdList"][group_i],
                                d["insCodeList"][group_i] == '\0' ? ' ' : d["insCodeList"][group_i],
                                [
                                    d["xCoordList"][atom_i],
                                    d["yCoordList"][atom_i],
                                    d["zCoordList"][atom_i],
                                ],
                                d["occupancyList"][atom_i],
                                d["bFactorList"][atom_i],
                                group["elementList"][ai],
                                # Add + to positive charges to match PDB convention
                                group["formalChargeList"][ai] > 0 ? "+$(group["formalChargeList"][ai])" :
                                            string(group["formalChargeList"][ai])
                            );
                            remove_disorder=remove_disorder)
                    end
                end
            end
        end
    end
    fixlists!(struc)
    return struc
end


"""
    writemmtf(output, element, atom_selectors...)
    writemmtf(output, mmtf_dict)

Write a `StructuralElementOrList` or a `MMTFDict` to a MMTF file or output
stream.

Atom selector functions can be given as additional arguments - only atoms
that return `true` from all the functions are retained.
The keyword argument `expand_disordered` (default `true`) determines whether to
return all copies of disordered residues and atoms.
The keyword argument `gzip` (default `false`) determines if the file should be
gzipped.
"""
function writemmtf(output::Union{AbstractString, IO},
                d::MMTFDict;
                gzip::Bool=false)
    writemmtf(d.dict, output; gzip=gzip)
    return
end

function writemmtf(filepath::AbstractString,
                el::StructuralElementOrList,
                atom_selectors::Function...;
                expand_disordered::Bool=true,
                gzip::Bool=false)
    open(filepath, "w") do output
        writemmtf(output, el, atom_selectors...;
                    expand_disordered=expand_disordered, gzip=gzip)
    end
end

generatechainid(i::Integer) = string(Char(64 + i))

function writemmtf(output::IO,
                el::StructuralElementOrList,
                atom_selectors::Function...;
                expand_disordered::Bool=true,
                gzip::Bool=false)
    d = MMTFDict()
    for mod in collectmodels(el)
        chain_i = 0
        for ch in mod
            # MMTF splits chains up by molecules so we determine chain splits
            #   at the residue level
            prev_resname = ""
            prev_het = true
            group_count = 0
            sequence = ""
            for res in collectresidues(ch; expand_disordered=expand_disordered)
                # Determine whether we have changed entity
                # ATOM blocks, and hetero molecules with the same name, are
                #   treated as the same entity
                if ishetero(res) != prev_het || (prev_het && resname(res) != prev_resname) || group_count == 0
                    chain_i += 1
                    push!(d["chainIdList"], generatechainid(chain_i))
                    push!(d["chainNameList"], chainid(ch))
                    # Add the groupsPerChain and sequence for the previous chain
                    if group_count > 0
                        push!(d["groupsPerChain"], group_count)
                        d["entityList"][end]["sequence"] = sequence
                        group_count = 0
                        sequence = ""
                    end
                    # Checking for similar entities is non-trivial so we treat
                    #   each molecule as a separate entity
                    push!(d["entityList"], Dict{Any, Any}(
                        "chainIndexList"=> Any[length(d["chainIdList"]) - 1],
                        "description"   => "",
                        "sequence"      => "", # This is changed later
                        "type"          => ishetero(res) ? "non-polymer" : "polymer"
                    ))
                end
                if !ishetero(res)
                    sequence *= string(AminoAcidSequence(res; gaps=false))
                end
                group_count += 1

                # Look for an existing group with the correct residue name and
                #   atom names present
                group_i = 0
                for (gi, group) in enumerate(d["groupList"])
                    if group["groupName"] == resname(res) && group["atomNameList"] == atomnames(res)
                        group_i = gi
                        break
                    end
                end

                if group_i == 0
                    push!(d["groupList"], Dict{Any, Any}(
                        "groupName"       => resname(res),
                        "bondAtomList"    => Any[],
                        "elementList"     => Any[element(at) for at in res],
                        "formalChargeList"=> Any[parse(Int64, charge(at)) for at in res],
                        "singleLetterCode"=> "",
                        "chemCompType"    => "",
                        "atomNameList"    => Any[atomnames(res)...],
                        "bondOrderList"   => Any[]
                    ))
                end
                push!(d["groupIdList"], resnumber(res))
                push!(d["groupTypeList"], group_i == 0 ? length(d["groupList"]) - 1 : group_i - 1)
                push!(d["insCodeList"], inscode(res) == ' ' ? '\0' : inscode(res))
                push!(d["secStructList"], -1)
                push!(d["sequenceIndexList"], ishetero(res) ? -1 : length(sequence) - 1)
                for at in collectatoms(res, atom_selectors...;
                                        expand_disordered=expand_disordered)
                    push!(d["altLocList"], altlocid(at) == ' ' ? '\0' : altlocid(at))
                    push!(d["atomIdList"], serial(at))
                    push!(d["bFactorList"], tempfactor(at))
                    push!(d["occupancyList"], occupancy(at))
                    push!(d["xCoordList"], x(at))
                    push!(d["yCoordList"], y(at))
                    push!(d["zCoordList"], z(at))
                end
                prev_resname = resname(res)
                prev_het = ishetero(res)
            end
            # Add the groupsPerChain and sequence for the last chain
            if group_count > 0
                push!(d["groupsPerChain"], group_count)
                d["entityList"][end]["sequence"] = sequence
            end
        end
        push!(d["chainsPerModel"], chain_i)
    end

    d["numModels"] = countmodels(el)
    d["numChains"] = length(d["chainIdList"])
    d["numGroups"] = length(d["groupIdList"])
    d["numAtoms"] = length(d["atomIdList"])
    d["structureId"] = structurename(el)
    d["mmtfVersion"] = "1.0.0"
    d["mmtfProducer"] = "BioStructures.jl"
    writemmtf(output, d; gzip=gzip)
end