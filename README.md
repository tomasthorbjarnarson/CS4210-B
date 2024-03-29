#  Modeling Complex Neural Networks as Constraint Optimization Problems

## Currently models very simple perceptron for XOR problem

### Setup
In this project ConditionalJuMP is used, which is not compatible with JuMP 0.19.*. It is therefor required to downrade (fix) the JuMP version used to 0.18.6. This can be done through the following steps:


```
add JuMP
pin JuMP@v0.18.6
add ConditionalJuMP
```

### How to run:

#### To run a single file:

```
julia src/nn.jl datasets/nn1/0-7-7.json
```

#### To run all files in a directory:

```
julia src/nn.jl datasets/nn1/
```

#### To create adversarial examples:

```
julia scr/nn.jl datasets/nn1/0-7-7.json --adversarial
```

##### To also write the output to JSON:

```
julia src/nn.jl datasets/nn1/0-7-7.json --adversarial --writeJSON
```

##### To also write the output to CSV:

```
julia src/nn.jl datasets/nn1/ --writeCSV
```

#### To visualize adversarial examples:

```
python img.py datasets/nn1/0-7-7.json
```

Which will show original input image from that dataset as well as the
adversarial input from adversarials/nn1/0-7-7.json
