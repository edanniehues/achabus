class RouteTracerController < ApplicationController
  skip_before_action :auth_basic_temp
  def trace
    @source = VirtualPoint.new(params[:src_lon], params[:src_lat])
    @destination = VirtualPoint.new(params[:dest_lon], params[:dest_lat])

    @path = RouteTracer.route_between(@source, @destination)
  end

  def walking_path
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    source = factory.parse_wkt("POINT (#{params[:src_lon]} #{params[:src_lat]})")
    dest = factory.parse_wkt("POINT (#{params[:dest_lon]} #{params[:dest_lat]})")

    render json: {route: RouteTracer.walking_path(source, dest).points.map{|p| {lng: p.lon, lat: p.lat}}}
  end
end
