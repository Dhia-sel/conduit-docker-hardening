package main

import rego.v1

deny contains msg if {
	n := count([c | some c in input.components; c.type == "library"])
	n > 250
	msg := sprintf("trop de paquets pour le backend : %d (maximum 250)", [n])
}