using Pkg
Pkg.activate("../")

using Plasmo
using MPI
using PipsSolver

MPI.Init()

function get_simple_model(demand)
    node = OptiNode()
    @variable(node, 0<=prod<=10, start=5)
    @variable(node, input)
    @variable(node, gas_purchased)
    @constraint(node, gas_purchased >= prod)
    @constraint(node, prod + input == demand)
    return m
end

#Setup processor information
Ns = 8
demand = rand(Ns)*10
comm = MPI.COMM_WORLD
ncores = MPI.Comm_size(comm)
rank = MPI.Comm_rank(comm)
SPP = round(Int, floor(Ns/ncores))

graph = ModelGraph()

#Create the master model
master = Model()
@variable(master,0<=gas_purchased<=8)
@objective(master,Min,gas_purchased)

#Add the master model to the graph
master_node = add_node!(graph,master)
scenm=Array{JuMP.Model}(undef,Ns)
scen_nodes = Array{ModelNode}(undef,Ns)
owned = []
s = 1
#split scenarios between processors
for j in 1:Ns
    global s
    if round(Int, floor((s-1)/SPP)) == rank
        push!(owned, s)
        #get scenario model and append to parent node
        scenm[j] = get_simple_model(demand[j])
        node = add_node!(graph,scenm[j])
        scen_nodes[j] = node

        #connect children and parent variables
        @linkconstraint(graph, master[:gas_purchased] == scenm[j][:gas_purchased])
        #reconstruct second stage objective
        @objective(scenm[j],Min,1/Ns*(scenm[j][:prod] + 3*scenm[j][:input]))
    else #Ghost nodes
        scenm[j] = OptiNode()
        node = add_node!(graph, scenm[j])
        scen_nodes[j] = node
    end
    s = s + 1
end
#create a link constraint between the subproblems (PIPS-NLP supports this kind of constraint)
#@linkconstraint(graph, (1/Ns)*sum(scenm[s][:prod] for s in 1:Ns) == 8)
@linkconstraint(graph, (1/Ns)*sum(scenm[s][:prod] for s in owned) == 8)


if rank == 0
    println("Solving with PIPS-NLP")
end
pipsnlp_solve(graph)
if rank == 0
    @show objective_value(graph)
end

MPI.Finalize()
