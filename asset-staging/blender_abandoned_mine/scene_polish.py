"""Shared production finishing sequence for both a rebuild and an existing mine."""
def prepare_meshes_for_export():
    import bpy, bmesh
    for mesh in bpy.data.meshes:
        if not mesh.users or not any(len(face.vertices) > 4 for face in mesh.polygons):
            continue
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.triangulate(bm, faces=[face for face in bm.faces if len(face.verts) > 4])
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()

def finish_scene(layout, report):
    import finish_mine
    import prop_contact
    import rock_detail
    import surface_contact
    import formation_contact
    import geology_materials
    report = finish_mine.finish_scene(layout, report)
    prop_contact.fix_scene(layout, report)
    # Scan placement reserves the final wall lamps and timber assemblies.
    report['geologic_detail'] = rock_detail.polish_scene(layout)
    report = surface_contact.fix_scene(layout, report)
    report = formation_contact.fix_scene(layout, report)
    report['continuous_geology'] = geology_materials.apply_continuous_geology()
    prepare_meshes_for_export()
    return report
