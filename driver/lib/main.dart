import 'package:flutter/material.dart';

void main()=>runApp(const RideGoDriver());

class RideGoDriver extends StatelessWidget {
 const RideGoDriver({super.key});
 @override Widget build(BuildContext c)=>MaterialApp(
  debugShowCheckedModeBanner:false,title:'RideGo Driver',
  theme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF1565C0)),
  home:const DriverHome());
}
class DriverHome extends StatefulWidget{const DriverHome({super.key});@override State<DriverHome>createState()=>_DriverHomeState();}
class _DriverHomeState extends State<DriverHome>{
 bool online=false;String status='Offline';int? rideId;
 void toggle()=>setState((){online=!online;status=online?'Online — waiting for rides':'Offline';});
 void accept()=>setState(()=>{rideId=1001,status='DRIVER_ACCEPTED'});
 void next(){
  if(status=='DRIVER_ACCEPTED')setState(()=>status='DRIVER_ARRIVED');
  else if(status=='DRIVER_ARRIVED')setState(()=>status='TRIP_STARTED');
  else if(status=='TRIP_STARTED')setState(()=>status='COMPLETED');
 }
 @override Widget build(BuildContext c)=>Scaffold(
 appBar:AppBar(title:const Text('RideGo Driver')),
 body:Padding(padding:const EdgeInsets.all(20),child:Column(
 mainAxisAlignment:MainAxisAlignment.center,children:[
  Icon(Icons.local_taxi,size:70,color:Theme.of(c).colorScheme.primary),
  const SizedBox(height:15),Text(status,style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
  const SizedBox(height:25),
  if(online&&rideId==null)Card(child:ListTile(
   leading:const Icon(Icons.notifications_active),title:const Text('New ride request'),
   subtitle:const Text('Pickup nearby • Estimated fare ₹120'),
   trailing:FilledButton(onPressed:accept,child:const Text('ACCEPT')))),
  if(rideId!=null&&status!='COMPLETED')SizedBox(width:double.infinity,height:50,
   child:FilledButton(onPressed:next,child:Text(
    status=='DRIVER_ACCEPTED'?'DRIVER ARRIVED':
    status=='DRIVER_ARRIVED'?'START TRIP':'COMPLETE TRIP'))),
  const SizedBox(height:18),
  SizedBox(width:double.infinity,height:50,child:OutlinedButton(
   onPressed:toggle,child:Text(online?'GO OFFLINE':'GO ONLINE')))
 ])));
}