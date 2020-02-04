// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*library: nnbd=false*/

// @dart = 2.5
import 'opt_in.dart';

/*class: Legacy:Legacy,Object*/
abstract class Legacy {
  /*member: Legacy.mandatory:void Function(int*)**/
  void mandatory(int param);
  /*member: Legacy.optional:void Function(int*)**/
  void optional(int param);
}

/*class: Both1:Both1,Legacy,Nnbd,Object*/
class Both1 implements Legacy, Nnbd {
  /*member: Both1.mandatory:void Function(int*)**/
  void mandatory(param) {}
  /*member: Both1.optional:void Function(int*)**/
  void optional(param) {}
}

/*class: Both2:Both2,Legacy,Nnbd,Object*/
class Both2 implements Nnbd, Legacy {
  /*member: Both2.mandatory:void Function(int*)**/
  void mandatory(param) {}
  /*member: Both2.optional:void Function(int*)**/
  void optional(param) {}
}