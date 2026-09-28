import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

void main()=>runApp(const RideGoRider());

class RideGoRider extends StatelessWidget {
 const RideGoRider({super.key});
 @override Widget build(BuildContext c)=>MaterialApp(
  debugShowCheckedModeBanner:false,title:'RideGo Rider',
  theme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF1565C0)),
  home:const RiderHome());
}

class RiderHome extends StatefulWidget{const RiderHome({super.key});@override State<RiderHome> createState()=>_RiderHomeState();}
class _RiderHomeState extends State<RiderHome>{
 GoogleMapController? map;
 LatLng pickup=const LatLng(17.3850,78.4867);
 LatLng? destination;
 String vehicle='Bike',status='Choose your destination';
 int fare=0;
 Future<void> locate()async{
  try{
   var p=await Geolocator.checkPermission();
   if(p==LocationPermission.denied)p=await Geolocator.requestPermission();
   final x=await Geolocator.getCurrentPosition();
   setState(()=>pickup=LatLng(x.latitude,x.longitude));
   map?.animateCamera(CameraUpdate.newLatLngZoom(pickup,15));
  }catch(_){}
 }
 void book(){if(destination==null)return;setState(()=>status='SEARCHING_DRIVER');Future.delayed(const Duration(seconds:2),(){if(mounted)setState(()=>status='DRIVER_ASSIGNED');});}
 @override Widget build(BuildContext c)=>Scaffold(
 body:Stack(children:[
  GoogleMap(initialCameraPosition:CameraPosition(target:pickup,zoom:14),
   myLocationEnabled:true,myLocationButtonEnabled:false,onMapCreated:(x)=>map=x,
   onTap:(p)=>setState(()=>destination=p),
   markers:{Marker(markerId:const MarkerId('pickup'),position:pickup),
    if(destination!=null)Marker(markerId:const MarkerId('destination'),position:destination!)}),
  SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[
   const CircleAvatar(child:Icon(Icons.person)),const SizedBox(width:10),
   const Expanded(child:Text('RideGo',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold))),
   IconButton.filledTonal(onPressed:locate,icon:const Icon(Icons.my_location))
  ]))),
  Positioned(left:0,right:0,bottom:0,child:Container(
   padding:const EdgeInsets.all(18),decoration:const BoxDecoration(color:Colors.white,
   borderRadius:BorderRadius.vertical(top:Radius.circular(24))),
   child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Align(alignment:Alignment.centerLeft,child:Text('Choose your ride',
     style:TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
    const SizedBox(height:8),
    SegmentedButton<String>(segments:const[
     ButtonSegment(value:'Bike',label:Text('Bike'),icon:Icon(Icons.two_wheeler)),
     ButtonSegment(value:'Auto',label:Text('Auto'),icon:Icon(Icons.electric_rickshaw)),
     ButtonSegment(value:'Cab',label:Text('Cab'),icon:Icon(Icons.local_taxi))],
     selected:{vehicle},onSelectionChanged:(s)=>setState(()=>vehicle=s.first)),
    const SizedBox(height:10),
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
     Text(status),Text(fare==0?'Fare calculated by server':'₹$fare',
      style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18))]),
    const SizedBox(height:10),
    SizedBox(width:double.infinity,height:50,child:FilledButton(
     onPressed:destination==null?null:book,child:const Text('BOOK RIDE')))
   ])))
 ]));
}