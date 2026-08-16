#include "res://shaders/sdf_lib.gdshaderinc"
#include "res://shaders/sdf_operations.gdshaderinc"
#include "res://shaders/sdf_spatial_manip.gdshaderinc"
#include "res://shaders/icons/currencies/shi_crystal_icon.gdshaderinc"

// Making a crystal boost hit harder: the crystal cluster itself, shrunk and set
// inside a burst. The cluster says which economy is being raised, the rays say
// it is the boost's strength rather than the crystal count - crystal_gain
// already owns the bare cluster.
float boost_power_icon(vec2 UVspace, float icon_scale)
{
	float cluster = crystal_icon(UVspace, icon_scale * 0.62);

	vec2 p = SpatialManipulation_CenterUVs(UVspace)/icon_scale;
	// Four rays on the diagonals, clear of the cluster's own points.
	vec2 d = SpatialManipulation_MirrorXY(p);
	float ray = SDF_LineSegment(d, vec2(0.56, 0.56), vec2(0.86, 0.86), 0.075);

	return max(cluster, Operation_HardShape(ray));
}
