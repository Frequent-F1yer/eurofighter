print("*** LOADING weapons.nas ... ***");
################################################################################
#
#                        m2005-5's WEAPONS SETTINGS
#
################################################################################

var TRUE = 1;
var FALSE = 0;

var dt = 0;
var isFiring = 0;
var splashdt = 0;
var MPMessaging = props.globals.getNode("/controls/armament/mp-messaging", 1);

#var trigger = func(b)
#{
#    setprop("/controls/armament/trigger", b);
#    if(getprop ("/gear/gear[2]/position-norm") == 0)
#    {
#        fire_MG(b);
#    }
#}

setlistener("/controls/armament/trigger", func() {
												#print("inside listener");
												if(getprop ("/gear/gear[2]/position-norm") == 0)
													{
														#print("trigger state: " ~ getprop("/controls/armament/trigger"));
														fire_MG(getprop("/controls/armament/trigger"));
													}
												}
);

setlistener("controls/armament/stick-selector", func() { setprop("/controls/armament/gun-trigger",0); } );
			
# keep armament messaging setting of damage.nas in sync with the legacy "MP messaging" flag
setlistener("/controls/armament/mp-messaging", func() {
    setprop("/payload/armament/msg", getprop("/controls/armament/mp-messaging"));
    # print("New payload armament messaging state: " ~ getprop("/payload/armament/msg")) 
});

fire_MG = func(b) {
    if(getprop("controls/armament/stick-selector") == 1){
          setprop("/controls/armament/gun-trigger", b);
    }
    elsif(getprop("/controls/armament/stick-selector") > 1)
    {
        if(b == 1)
        {
			var pylon = getprop("/controls/armament/missile/current-pylon");
			load.dropLoad(pylon);
        }
    }
}

reload_Cannon = func() {
    setprop("/ai/submodels/submodel/count",    150);
    setprop("/ai/submodels/submodel[1]/count", 150);
    setprop("/ai/submodels/submodel[2]/count", 150);
    setprop("/ai/submodels/submodel[3]/count", 150);
}


input = {
  elapsed:          "/sim/time/elapsed-sec",
  impact:           "/ai/models/model-impact",
};

foreach(var name; keys(input)) {
      input[name] = props.globals.getNode(input[name], 1);
}

############ Cannon impact messages #####################

var last_impact = 0;

var hit_count = 0;

var hits_count = 0;
var hit_timer  = nil;
var hit_callsign = "";

var Mp = props.globals.getNode("ai/models");
var valid_mp_types = {
	multiplayer: 1, tanker: 1, aircraft: 1, ship: 1, groundvehicle: 1,
};

# Find a MP aircraft close to a given point (code from the Mirage 2000)
var findmultiplayer = func(targetCoord, dist) {
	if(targetCoord == nil) {
		return nil;
	}

	var raw_list = Mp.getChildren();
	var SelectedMP = nil;
	foreach (var c ; raw_list) {
		var is_valid = c.getNode("valid");
		if (is_valid == nil or !is_valid.getBoolValue()) {
			continue;
		}

		var type = c.getName();

		var position = c.getNode("position");
		var name = c.getValue("callsign");
		if	(name == nil or name == "") {
			# fallback, for some AI objects
			var name = c.getValue("name");
		}
		if(position == nil or name == nil or name == "" or !contains(valid_mp_types, type)) {
			continue;
		}

		var lat = position.getValue("latitude-deg");
		var lon = position.getValue("longitude-deg");
		var elev = position.getValue("altitude-ft") * FT2M;

		if(lat == nil or lon == nil or elev == nil) {
			continue;
		}

		MpCoord = geo.Coord.new().set_latlon(lat, lon, elev);
		var tempoDist = MpCoord.direct_distance_to(targetCoord);
		if(dist > tempoDist) {
			dist = tempoDist;
			SelectedMP = name;
		}
	}
	return SelectedMP;
}

var impact_listener = func {
	var ballistic_name = props.globals.getNode("/ai/models/model-impact").getValue();
	var ballistic = props.globals.getNode(ballistic_name, 0);
	if (ballistic != nil and ballistic.getName() != "munition") {
		var typeNode = ballistic.getNode("impact/type");
		if (typeNode != nil and typeNode.getValue() != "terrain") {
			var lat = ballistic.getNode("impact/latitude-deg").getValue();
			var lon = ballistic.getNode("impact/longitude-deg").getValue();
			var elev = ballistic.getNode("impact/elevation-m").getValue();
			var impactPos = geo.Coord.new().set_latlon(lat, lon, elev);
			var target = findmultiplayer(impactPos, 80);

			if (target != nil) {
				var typeOrd = ballistic.getNode("name").getValue();
				if (target == hit_callsign) {
					# Previous impacts on same target
					hits_count += 1;
				} else {
					if (hit_timer != nil) {
						# Previous impacts on different target, flush them first
						hit_timer.stop();
						hitmessage(typeOrd);
					}
					hits_count = 1;
					hit_callsign = target;
					hit_timer = maketimer(1, func {hitmessage(typeOrd);});
					hit_timer.singleShot = 1;
					hit_timer.start();
				}
			}
		}
	}
}

var hitmessage = func(typeOrd) {
	var phrase = typeOrd ~ " hit: " ~ hit_callsign ~ ": " ~ hits_count ~ " hits";
    # print("hitmessage(): " ~ phrase);
	if (getprop("payload/armament/msg") == TRUE) {
		#armament.defeatSpamFilter(phrase);
		var msg = notifications.ArmamentNotification.new("mhit", 4, -1*(damage.shells[typeOrd][0]+1));
		msg.RelativeAltitude = 0;
		msg.Bearing = 0;
		msg.Distance = hits_count;
		msg.RemoteCallsign = hit_callsign;
		notifications.hitBridgedTransmitter.NotifyAll(msg);
        var str = "You hit "~hit_callsign~" with "~typeOrd~", "~hits_count~" times.";
		damage.damageLog.push(str);
        print("hitmessage(): " ~ str);
        # display the message to the user
        # (currently not required as MP attack messages are anyway duplicated on ATC)
        # setprop("/sim/messages/atc", str);
	} else {
		setprop("/sim/messages/atc", phrase);
	}
	hit_callsign = "";
	hit_timer = nil;
	hits_count = 0;
}


var spams = 0;

var defeatSpamFilter = func (str) {
  spams += 1;
  if (spams == 15) {
    spams = 1;
  }
  str = str~":";
  for (var i = 1; i <= spams; i+=1) {
    str = str~".";
  }
  var myCallsign = getprop("sim/multiplay/callsign");
  if (myCallsign != nil and find(myCallsign, str) != -1) {
      str = myCallsign~": "~str;
  }
  var newList = [str];
  for (var i = 0; i < size(spamList); i += 1) {
    append(newList, spamList[i]);
  }
  spamList = newList;  
}


# setup impact listener
setlistener("/ai/models/model-impact", impact_listener, 0, 0);

