# frozen_string_literal: true

# Description Two file paths are required to prevent destructive changes to the original file

load_path = OpenStudio::Path.new('C:\Users\luislara\Desktop\seed.osm')
output_file_path = OpenStudio::Path.new('C:\Users\luislara\Desktop\target.osm')
model = osload(load_path)
# Get a construction from the model, change to match your spandrel construction
spandrel_construction = model.getConstructionByName('Typical Insulated Steel Framed Exterior Wall R-8.06').get
# Change the spandrel height to match whatever you want your spandrel to be (meters)
spandrel_height = 0.9144
# Loop through all of the subsurfaces

model.getSubSurfaces.each do |w|
  ss_v = w.vertices
  # Create an array to collect the existing two bottom vertices
  bottom_vertices = []
  # Absurd initial numbers for min and max
  min_z = 978
  max_z = -978
  # Get the minimum elevation for the window
  ss_v.each do |v|
    next if min_z <= v.z

    min_z = v.z
  end
  # Get the maximum elevation for the window
  ss_v.each do |v|
    next if max_z >= v.z

    max_z = v.z
  end
  # Add the bottom vertices to an array
  ss_v.each do |v|
    # Tolerance for small differences in Z coordinates
    difference = min_z - v.z
    next unless difference.abs < 0.01

    bottom_vertices << v
  end
  window_ht = max_z - min_z
  # Create an array for new vertices
  window_vertices = []
  spandrel_vertices = []
  # Create the new top vertices
  original_w_ht = OpenStudio::Vector3d.new(0, 0, window_ht)
  # Add an extra inch to the reduction vector to prevent spandrels to go outside original surface.
  red_ht_vector = OpenStudio::Vector3d.new(0, 0, (-1 * spandrel_height - 0.0254))
  spandrel_separation = OpenStudio::Vector3d.new(0, 0, 0.0254)
  spandrel_ht_vector = OpenStudio::Vector3d.new(0, 0, spandrel_height)
  # Substract the spandrel height from the vector.
  number = 1
  # Vertices have to be either clockwise or counterclockwise to the normal of the base surface
  # This is an ugly workaround, if someone has an algorithm to fix this plx share thx
  bottom_vertices.each do |v|
    case number
    when 1
      # Window Vertices, Bottom First
      window_vertices << v
      vertex = v + original_w_ht + red_ht_vector
      window_vertices << vertex
      # Spandrel Vertices, Bottom first
      bt_sp_vertex = vertex + spandrel_separation
      top_sp_vertex = bt_sp_vertex + spandrel_ht_vector
      spandrel_vertices << bt_sp_vertex
      spandrel_vertices << top_sp_vertex
      # Make it so that the next iteration the other configuration is chosen
      number = 2
    when 2
      # Window Vertices, Top First
      vertex = v + original_w_ht + red_ht_vector
      window_vertices << vertex
      window_vertices << v
      # Spandrel Vertices, Top first
      bt_sp_vertex = vertex + spandrel_separation
      top_sp_vertex = bt_sp_vertex + spandrel_ht_vector
      spandrel_vertices << top_sp_vertex
      spandrel_vertices << bt_sp_vertex
      # Make it so that the next iteration the other configuration is chosen
      number = 1
    end
  end
  # Create Spandrel Surface
  existing_s = w.surface.get
  spandrel = OpenStudio::Model::SubSurface.new(spandrel_vertices.reverse,model)
  spandrel.setSurface(existing_s)
  spandrel.setConstruction(spandrel_construction)
  # Create as a door so that it can have an opaque construction
  spandrel.setSubSurfaceType('Door')

  w.setVertices(window_vertices.reverse)
end

model.save(output_file_path, true)
