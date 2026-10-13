package main

import rego.v1

# Outils qui ne doivent pas se trouver dans une image livrée
forbidden := {"npm", "gcc", "g++", "make", "git", "python3", "wget", "curl", "libcurl"}
libs := [c | some c in input.components; c.type == "library"]

deny contains msg if {
	some c in libs
	c.name in forbidden
	msg := sprintf("composant interdit dans l'image finale : %s %s", [c.name, object.get(c, "version", "?")])
}

deny contains msg if {
	some c in libs
	object.get(c, "version", "") == ""
	msg := sprintf("paquet sans version : %s", [c.name])
}

# curl : decision en attente, donc simple avertissement
warn contains msg if {
	some c in libs
	c.name in {"curl", "libcurl"}
	msg := sprintf("outil reseau present : %s %s", [c.name, object.get(c, "version", "?")])
}