import 'package:flutter/material.dart';

import '../../host_contracts.dart';
import '../../access/access.dart';
import 'listening.dart';

Widget buildListeningFeature(StudyRoomHost host, StudyRoomAccess access) =>
    ListeningFeature(host, access);
