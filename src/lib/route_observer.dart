import 'package:flutter/material.dart';

/// App-level visibility includes modal routes such as dialogs and bottom sheets.
final appRouteObserver = RouteObserver<ModalRoute<dynamic>>();

/// Course media lifecycle only follows full page transitions.
final courseRouteObserver = RouteObserver<PageRoute<dynamic>>();
