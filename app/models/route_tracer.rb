require 'ruby-prof'
require 'priority_queue'

class RouteTracer
  @point_cache = []

  def self.calculate_point_cache
    @point_cache.clear
    i = 1
    count = RoutePoint.count
    RoutePoint.all.includes(:point).each do |rp|
      puts "#{i}/#{count}..."
      rp.cached_costs = {}
      rp.neighbors(nil, nil).each do |neighbor|
        print "*"
        rp.cached_costs[neighbor] = rp.cost_to neighbor
      end
      puts ""
      @point_cache << rp
      i += 1
    end
    save_point_cache
  end

  def self.save_point_cache
    serialized = @point_cache.map{|rp| [rp.id, rp.cached_costs.map{|n,c| [n.id, c]}.to_h]}.to_h
    File.write('/tmp/achabus-point-cache.json', serialized.to_json)
  end

  def self.load_point_cache
    begin
      id_hash = JSON.parse(File.read('/tmp/achabus-point-cache.json'))
    rescue
      calculate_point_cache && save_point_cache && load_point_cache
      return
    end
    puts "Carregando..."
    @point_cache = RoutePoint.includes(:route).find(id_hash.keys)
    @point_cache.each do |rp|
      print "-> "
      rp.cached_costs = id_hash[rp.id.to_s].map do |k, v|
        print "*"
        [RoutePoint.includes(:route).find(k), v]
      end.to_h
      puts ""
    end
  end

  def self.walking_distance(a, b)
    id1 = a.nearest_ways_point
    id2 = b.nearest_ways_point

    sql = "
    SELECT SUM(ST_Length(the_geom::geography))
    FROM pgr_dijkstra('
      SELECT gid as id, source, target, cost, reverse_cost FROM routing.ways
      WHERE the_geom && ST_Expand(
      (SELECT ST_Collect(the_geom) FROM routing.ways_vertices_pgr WHERE id IN (#{id1}, #{id2})), 0.007)'
    , #{id1}, #{id2}, false) dij
    LEFT JOIN routing.ways ON dij.node = gid"
    res = ApplicationRecord.connection.execute(sql).values[0][0]
    res || a.point.position.distance(b.point.position)
  end

  # Aqui temos um modelo simples para aceleração/desaceleração de um ônibus.
  # Fazemos de conta que ônibus têm aceleração constante, 1 m/s, até chegarem a 11 m/s (39,6 km/h).
  # Após ficarem pelo menos 330 m nessa velocidade (30s) eles aceleram para 17 m/s a 1 m/s², demorando 6 segundos.
  # Depois disso, independentemente da velocidade que estão, freiam a -1 m/s² para parar no próximo ponto.
  #
  # A distância de aceleração é igual a integral da aceleração sobre o tempo. Como temos aceleração linear, para a
  # aceleração inicial e desaceleração final temos um triângulo, e para a aceleração no meio do percurso, temos um
  # quadrilátero.
# @param [Float] length o percurso entre um ponto e outro
# @return [Float] o tempo em segundos
  def self.driving_time(length)
    # 121 é a distância necessária para acelerar até 11 m/s e parar.
    if length <= 121
      # O nosso gráfico de velocidade/tempo fica assim:
      #     /\
      #    /  \
      #   /    \
      #  /      \
      # ---------
      #    x | y
      # Os dois lados são iguais, x + x = length, logo,
      length/2
    elsif length > 121 && length <= 451
      # Nosso gráfico é um trapézio isósceles neste caso.
      #    /---------\
      #   /           \
      #  /             \
      # /               \
      # -----------------
      # O ônibus usa 60,5m para acelerar até 11 m/s e o mesmo espaço para parar.
      # Portanto, para percursos entre 121 m e 451 m (121 + 330 para acelerar até quase 60 km/h), temos MRV no meio do
      # percurso.
      22 + (length - 121)/11
    elsif length > 451 && length <= 679.5 # ???
      # A distância que percorremos para acelerar de 11 m/s para 17 m/s é:
      # Um retângulo com altura 11 e base 6 + um triângulo com base 6 e altura 6. Assim: d = 84 m
      # Mais 121 para acelerar, 330 para manter, e 17*17/2 para desacelerar, temos então 679,5 m para cairmos no último
      # if.
      #
      # O gráfico aqui é assim, e temos que achar x e y:
      #
      #        /\
      #       /  \
      #   /---    \
      #  / length  \
      # /           \
      # -------------
      # Mas o tempo para chegar até a acelerada nós já conhecemos, é 11s + 30s (41s), que são 60,5 m + 330 m (390,5 m).
      # Se descontarmos este valor da área (length), ficamos com a área somente desta figura aqui:
      #   /\
      #  /  \
      # |\   \
      # |17\  \
      # |    \ \
      # |-------
      # Precisamos saber o comprimento da diagonal primeiro para aí conseguir saber a altura do quadrilátero.
    else
      # Aqui temos dois trapézios isósceles.
      #             /----\
      #            /b ----\
      #   /----------------\
      #  / a                \
      # /                    \
      # ----------------------
      # 11 |  30  |x | 11
    end

  end

# Aqui assumimos que pessoas andam em velocidade constante.
# A wikipédia diz que a maioria das pessoas anda a 1,4 m/s, então vamos usar este valor.
# t = d/v
#
# @param [RoutePoint||VirtualPoint] a ponto A
# @param [RoutePoint||VirtualPoint] b ponto B
# @return [Float] o tempo em segundos
  def self.walking_time(a, b)

    walking_distance(a, b)/1.4
  end

  def self.closest_street_vertex(point)
    sql = "
SELECT id FROM routing.ways_vertices_pgr
WHERE the_geom::geography <-> st_point(#{point.lon}, #{point.lat})::geography < 300
ORDER BY the_geom <-> st_point(#{point.lon}, #{point.lat})::geography
LIMIT 1"
    ApplicationRecord.connection.execute(sql).values[0][0]
  end

  def self.walking_path(a, b)
    id1 = closest_street_vertex a
    id2 = closest_street_vertex b

    sql = "
    SELECT st_asText(the_geom::geography), st_asText(st_reverse(the_geom)::geography) as flip_geom, source, target
    FROM pgr_dijkstra('
      SELECT gid as id, source, target, cost, reverse_cost FROM routing.ways
      WHERE the_geom && ST_Expand(
      (SELECT ST_Collect(the_geom) FROM routing.ways_vertices_pgr WHERE id IN (#{id1}, #{id2})), 0.007)'
    , #{id1}, #{id2}, false) dij
    LEFT JOIN routing.ways ON dij.node = gid"
    source = id1
    points = []
    ApplicationRecord.connection.execute(sql).values.each do |row|
      line = row[0]
      if source != row[2]
        line = row[1]
        source = row[2]
      else
        source = row[3]
      end
      points += RGeo::Geographic.spherical_factory(srid: 4326).parse_wkt(line).points
    end
    ls = "LINESTRING (#{points.uniq.map{|p| "#{p.lon} #{p.lat}"}.join(',')})"
    puts ls
    points.empty? ? OpenStruct.new({points: []}) : RGeo::Geographic.spherical_factory(srid: 4326).parse_wkt(ls)
  end

  def self.heuristic(a, b)
    if a == RoutePoint && b == RoutePoint && a.route_id == b.route_id
      a.point.position.distance(b.point.position)
    else
      5*a.point.position.distance(b.point.position)
    end
  end

  def self.antecessors_to(target, previous)
    path = []
    current = target
    while previous[current]
      path.unshift current
      current = previous[current]
    end
    path
  end

  def self.a_star(source, target)
    maxint = (2**(0.size * 8 -2) -1)
    costs = {}
    previous = {}
    nodes = PriorityQueue.new

    ([source, target] + @point_cache).each do |rp|
      if rp == source
        costs[rp] = 0
        nodes[rp] = 0
      else
        costs[rp] = maxint
        nodes[rp] = maxint
      end
      previous[rp] = nil
    end

    while nodes.length > 0
      current = nodes.delete_min_return_key

      if current == target
        return antecessors_to(current, previous)[0..-2]
      end

      break if current.nil? || costs[current] == maxint

      current.neighbors(target, antecessors_to(current, previous)).each do |new|
        alt = costs[current] + current.cost_to(new)
        if alt < costs[new]
          costs[new] = alt + heuristic(target, new)
          previous[new] = current
          nodes[new] = alt
        end
      end
    end

    []
  end

  def self.trace_route(start, finish)
    a_star(start, finish)
  end

  def self.route_between(start, finish)
    begin
      RubyProf.start
      old_level = ActiveRecord::Base.logger.level
      ActiveRecord::Base.logger.level = 1
      load_point_cache if @point_cache.empty?

      route = trace_route(start, finish)

      ActiveRecord::Base.logger.level = old_level
    ensure
      res = RubyProf.stop
      RubyProf::GraphHtmlPrinter.new(res).print(File.open("/tmp/report.html", "w"), min_percent: 1)
    end
    File.open('/tmp/route-trace.txt', 'w') do |f|
      f << "DISCRIMINAÇÃO DOS PONTOS\n\n"
      route.each do |rp|
        f << "%s - %s/%s\n  %s\n" % [rp.route.line.identifier, rp.route.origin, rp.route.destination, rp.point.name]
      end
    end
    route.group_by{|p| p.route_id}.map do |route_id, group|
      group = group.sort_by { |rp| rp.order } # ????
      sql = <<-EOF
SELECT st_astext(st_makeline(geom)::geography) as route_line
FROM
(
  SELECT (st_dumppoints(route)).geom FROM routes WHERE id = #{route_id} LIMIT (#{group[-1].polyline_index - group[0].polyline_index} + 1) OFFSET #{group[0].polyline_index}
) foo
      EOF
      path = RGeo::Geographic.spherical_factory(srid: 4326).parse_wkt(Route.connection.execute(sql).values[0][0])
      {
          start_point: start,
          end_point: finish,
          points: group.map(&:point),
          route: group[0].route,
          route_path: path&.points&.map do |p|
            p = RGeo::Geographic.spherical_factory(srid: 4326).parse_wkt(p.to_s)
            {lat: p.lat, lng: p.lon}
          end
      }
    end
  end

  def self.test_route
    old_level = ActiveRecord::Base.logger.level
    ActiveRecord::Base.logger.level = 1
    boicy = VirtualPoint.new -54.577825, -25.546901
    rodo  = VirtualPoint.new -54.562939, -25.520758
    ActiveRecord::Base.logger.level = old_level
    route_between boicy, rodo
  end
end
