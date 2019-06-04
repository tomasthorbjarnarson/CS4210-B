using JuMP
using Gurobi
using Distributions
using LinearAlgebra
using DelimitedFiles
using Printf
using ConditionalJuMP

import JSON

include("helper/printHelper.jl")
include("helper/problemLoader.jl")

"""
Add constraints for neural network, then optimize.
"""
function modelNN(input, w, b, label, layerSizes, doAdversarial)
  
  m = Model(solver=GurobiSolver())

  numLayers = size(layerSizes,1)

  # Initialize x decision variable, x >= 0. x[k,j] is x^k_j. Arbitrary upper bound of 10000
  @variable(m, 0 <= x[k=1:numLayers, j=1:layerSizes[k]] <= 10000)
  # Initialize s decision variable, s >= 0. s[k,j] is s^k_j
  @variable(m, 0 <= s[k=2:numLayers, j=1:layerSizes[k]] <= 10000)

  if doAdversarial
    # Introduce d variable, represents distance between input and adversarial input
    @variable(m, 0 <= d[1,j=1:layerSizes[1]] <= 10000)

    firstLayerX = [x[1,j] for j in 1:layerSizes[1]]
    firstLayerD = [d[1,j] for j in 1:layerSizes[1]]

    # Input must be in range 0 to 1
    @constraint(m, firstLayerX .<= .1)
    # Constrain d to be distance between original input and x input
    @constraint(m, -firstLayerD .<= firstLayerX - input)
    @constraint(m, firstLayerD .>= firstLayerX - input)
  else
    # First x layer must be equal to the input
    @constraint(m, [x[1,j] for j in 1:layerSizes[1]] .== input)
  end

  for k in 2:numLayers
    # x_j and s_j are values for layer k, j in 1:n_k
    layerX = [x[k,j] for j in 1:layerSizes[k]]
    layerS = [s[k,j] for j in 1:layerSizes[k]]

    weights = w[string(k-1)]
    biases = b[string(k-1)]
    lastLayer = [x[k-1,j] for j in 1:layerSizes[k-1]]

    # ReLU formulation, w^{k-1}^T * x^{k-1} + b^{k-1} = x^k - s^k
    @constraint(m, transpose(weights) * lastLayer + biases .== layerX .- layerS)

    # Either s or x must be 0
    for j in 1:layerSizes[k]
      @disjunction(m, (x[k,j] == 0), (s[k,j] == 0))
    end
  end

  # Only do the following if output has a hard constraint (i.e. adversarial)
  if doAdversarial
    # Constrain output to be equal to expected output
    output = [x[numLayers,j] for j in 1:layerSizes[numLayers,]]
    for k in 1:layerSizes[numLayers]
      if k != label+1
        @constraint(m, x[numLayers,label+1] >= 1.2*x[numLayers,k])
      end
    end
  end

  if doAdversarial
    # Minimize distance between original input and adversarial input
    @objective(m, Min, sum(d))
  else
    # Minimize over all x. Since input is fixed, this does not really do anything
    @objective(m, Min, sum(x))
  end

  print("Solver time: $(@elapsed(solve(m)))")
  return m,x,s
end



function writeInputToJSON(input, targetLabel, modelPredLabel, filename)
  data = Dict("input" => input, "label" => targetLabel, "predictedLabel" => modelPredLabel)
  json_data = JSON.json(data)
  open(filename, "w") do f
    write(f, json_data)
  end
end

function getRunResults(m)
  value = getobjectivevalue(m)
  solvetime = getsolvetime(m)
  bound = getobjectivebound(m)
  nodes = getnodecount(m)
  gap = abs(value - bound)/value
  return value,solvetime,bound,nodes,gap
end

function main()
  # Read JSON file
  path = ARGS[1]
  if occursin(".json", path)
    files = [path]
  else
    files = ["$path$f" for f in readdir(path)]
  end
  # Set to true if output label is hard constraint (i.e. adversarial)
  doAdversarial = false
  # Set to true to write adversarial to JSON
  writeToJSON = false
  # Set to true to write to csv
  writeToCSV = false
  # Set to true to see all the weights when printing
  printWeights = false
  if "--adversarial" in ARGS
    doAdversarial = true
  end
  if "--writeJSON" in ARGS
    writeToJSON = true
  end
  if "--writeCSV" in ARGS
    writeToCSV = true
  end

  sameAsNN = 0
  sameAsTrue = 0
  NNequalToTrue = 0
  numImages = length(files)

  csvData = zeros((numImages, 8))
  counter = 0

  for file in files
    println(file)
    counter += 1
    # Load data from file
    layers,input,label,predLabel,w,b = loadData(file)
    # Normalize input
    input = input/findmax(input)[1]

    targetLabel = label
    if doAdversarial
      targetLabel = (label + 5) % 10
    end

    println("Now constraining!")
    t = @elapsed m,x,s = modelNN(input,w,b,targetLabel,layers,doAdversarial)
    println(" ")
    println("Time: ",t)
    printVars(m,x,s,w,b,layers,label,predLabel,printWeights)
    modelPredLabel = getPredictedLabel(m,x,layers)

    if predLabel == modelPredLabel
      sameAsNN += 1
    end
    if label == modelPredLabel
      sameAsTrue += 1
    end
    if label == predLabel
      NNequalToTrue +=1
    end

    if doAdversarial && writeToJSON
      new_input = [getvalue(x[1,j]) for j in 1:layers[1]]
      advFileName = replace(file, "datasets" => "adversarials")
      writeInputToJSON(new_input, targetLabel, modelPredLabel, advFileName)
    end

    value,solvetime,bound,nodes,gap = getRunResults(m)
    csvData[counter,:] = [label, predLabel, modelPredLabel, value, bound, gap, solvetime, nodes]
    
  end
  if writeToCSV
    csvFileName = replace(path, "datasets/" => "")
    csvFileName = replace(csvFileName, ".json" => "")
    csvFileName = replace(csvFileName, "/" => "")
    writedlm("$csvFileName-adversarial.csv", csvData)
  end

  println("Total number of instances: $numImages")
  println("Number of labels equal to NN prediction: $sameAsNN")
  println("Number of labels equal to True labels: $sameAsTrue")
  println("Number of NN predictions equal to True labels: $NNequalToTrue")
  
end


main()