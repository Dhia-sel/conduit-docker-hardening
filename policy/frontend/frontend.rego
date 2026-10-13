package main

import rego.v1

# Le frontend est servi par nginx : Node n'a rien a y faire
deny contains msg if {
	some c in input.components
	c.name == "node"
	msg := "node present dans l'image frontend finale"
}

# Un site statique n'a besoin que de quelques paquets
deny contains msg if {
	n := count([c | some c in input.components; c.type == "library"])
	n > 40
	msg := sprintf("trop de paquets pour un frontend : %d (maximum 40)", [n])
}