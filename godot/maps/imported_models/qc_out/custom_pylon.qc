$modelname "props_pootis/custom_pylon.mdl"
$body "Body" "custom_pylon_ref.smd"
$staticprop
$surfaceprop "metal"
$cdmaterials "models/props_pootis/"
$sequence "idle" "custom_pylon_ref.smd"
$collisionmodel "custom_pylon_ref.smd" {
	$concave
	$automass
}
