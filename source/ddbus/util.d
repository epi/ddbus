module ddbus.util;

import ddbus.thin;
import std.typecons;
import std.range;
import std.traits;

struct DictionaryEntry(K, V) {
  K key;
  V value;
}

auto byDictionaryEntries(K, V)(V[K] aa) {
  import std.algorithm : map;

  return aa.byKeyValue.map!(pair => DictionaryEntry!(K, V)(pair.key, pair.value));
}

template isVariant(T) {
  static if(isBasicType!T || isInputRange!T) {
    enum isVariant = false;
  } else static if(__traits(compiles, TemplateOf!T) 
                && __traits(isSame, TemplateOf!T, Variant)) {
    enum isVariant = true;
  } else {
    enum isVariant = false;
  }
}

template VariantType(T) {
  alias VariantType = TemplateArgsOf!(T)[0];
}

template allCanDBus(TS...) {
  static if (TS.length == 0) {
    enum allCanDBus = true; 
  } else static if(!canDBus!(TS[0])) {
    enum allCanDBus = false;
  } else {
    enum allCanDBus = allCanDBus!(TS[1..$]);
  }
}

template basicDBus(T) {
  static if(is(T == byte) || is(T == short) || is (T == ushort) || is (T == int)
            || is (T == uint) || is (T == long) || is (T == ulong)
            || is (T == double) || is (T == string) || is(T == bool)
            || is (T == ObjectPath)) {
    enum basicDBus = true;
  } else static if(is(T B == enum)) {
    enum basicDBus = basicDBus!B;
  } else static if(isInstanceOf!(BitFlags, T)) {
    alias TemplateArgsOf!T[0] E;
    enum basicDBus = basicDBus!E;
  } else {
    enum basicDBus = false;
  }
}

template canDBus(T) {
  static if(basicDBus!T || is(T == DBusAny)) {
    enum canDBus = true;
  } else static if(isVariant!T) {
    enum canDBus = canDBus!(VariantType!T);
  } else static if(isTuple!T) {
    enum canDBus = allCanDBus!(T.Types);
  } else static if(isInputRange!T) {
    static if(is(ElementType!T == DictionaryEntry!(K, V), K, V)) {
      enum canDBus = basicDBus!K && canDBus!V;
    } else {
      enum canDBus = canDBus!(ElementType!T);
    }
  } else static if(isAssociativeArray!T) {
    enum canDBus = basicDBus!(KeyType!T) && canDBus!(ValueType!T);
  } else static if(is(T == struct) && !isInstanceOf!(DictionaryEntry, T)) {
    enum canDBus = allCanDBus!(Fields!T);
  } else {
    enum canDBus = false;
  }
}

unittest {
  import dunit.toolkit;
  (canDBus!int).assertTrue();
  (canDBus!(int[])).assertTrue();
  (allCanDBus!(int,string,bool)).assertTrue();
  (canDBus!(Tuple!(int[],bool,Variant!short))).assertTrue();
  (canDBus!(Tuple!(int[],int[string]))).assertTrue();
  (canDBus!(int[string])).assertTrue();
}

string typeSig(T)() if(canDBus!T) {
  static if(is(T == byte)) {
    return "y";
  } else static if(is(T == bool)) {
    return "b";
  } else static if(is(T == short)) {
    return "n";
  } else static if(is(T == ushort)) {
    return "q";
  } else static if(is(T == int)) {
    return "i";
  } else static if(is(T == uint)) {
    return "u";
  } else static if(is(T == long)) {
    return "x";
  } else static if(is(T == ulong)) {
    return "t";
  } else static if(is(T == double)) {
    return "d";
  } else static if(is(T == string)) {
    return "s";
  } else static if(is(T == ObjectPath)) {
    return "o";
  } else static if(isVariant!T) {
    return "v";
  } else static if(is(T B == enum)) {
    return typeSig!B;
  } else static if(isInstanceOf!(BitFlags, T)) {
    alias TemplateArgsOf!T[0] E;
    return typeSig!E;
  } else static if(is(T == DBusAny)) {
    static assert(false, "Cannot determine type signature of DBusAny. Change to Variant!DBusAny if a variant was desired.");
  } else static if(isTuple!T) {
    string sig = "(";
    foreach(i, S; T.Types) {
      sig ~= typeSig!S();
    } 
    sig ~= ")";
    return sig;
  } else static if(isInputRange!T) {
    return "a" ~ typeSig!(ElementType!T)();
  } else static if(isAssociativeArray!T) {
    return "a{" ~ typeSig!(KeyType!T) ~ typeSig!(ValueType!T) ~ "}";
  } else static if(is(T == struct)) {
    string sig = "(";
    foreach(i, S; Fields!T) {
      sig ~= typeSig!S();
    }
    sig ~= ")";
    return sig;
  }
}

string typeSig(T)() if(isInstanceOf!(DictionaryEntry, T)) {
  alias typeof(T.key) K;
  alias typeof(T.value) V;
  return "{" ~ typeSig!K ~ typeSig!V ~ '}';
}

string[] typeSigReturn(T)() if(canDBus!T) {
  static if(is(T == Tuple!TS, TS...))
    return typeSigArr!TS;
  else
    return [typeSig!T];
}

string typeSigAll(TS...)() if(allCanDBus!TS) {
  string sig = "";
  foreach(i,T; TS) {
    sig ~= typeSig!T();
  }
  return sig;
}

string[] typeSigArr(TS...)() if(allCanDBus!TS) {
  string[] sig = [];
  foreach(i,T; TS) {
    sig ~= typeSig!T();
  }
  return sig;
}

int typeCode(T)() if(canDBus!T) {
  int code = typeSig!T()[0];
  return (code != '(') ? code : 'r';
}

int typeCode(T)() if(isInstanceOf!(DictionaryEntry, T) && canDBus!(T[])) {
  return 'e';
}

unittest {
  import dunit.toolkit;
  // basics
  typeSig!int().assertEqual("i");
  typeSig!bool().assertEqual("b");
  typeSig!string().assertEqual("s");
  typeSig!(Variant!int)().assertEqual("v");
  // enums
  enum E : byte { a, b, c }
  typeSig!E().assertEqual(typeSig!byte());
  enum U : string { One = "One", Two = "Two" }
  typeSig!U().assertEqual(typeSig!string());
  // bit flags
  enum F : uint { a = 1, b = 2, c = 4 }
  typeSig!(BitFlags!F)().assertEqual(typeSig!uint());
  // tuples (represented as structs in DBus)
  typeSig!(Tuple!(int,string,string)).assertEqual("(iss)");
  typeSig!(Tuple!(int,string,Variant!int,Tuple!(int,"k",double,"x"))).assertEqual("(isv(id))");
  // structs
  struct S1 { int a; double b; string s; }
  typeSig!S1.assertEqual("(ids)");
  struct S2 { Variant!int c; string d; S1 e; uint f; }
  typeSig!S2.assertEqual("(vs(ids)u)");
  // arrays
  typeSig!(int[]).assertEqual("ai");
  typeSig!(Variant!int[]).assertEqual("av");
  typeSig!(Tuple!(byte)[][]).assertEqual("aa(y)");
  // dictionaries
  typeSig!(int[string]).assertEqual("a{si}");
  typeSig!(DictionaryEntry!(string, int)[]).assertEqual("a{si}");
  // multiple arguments
  typeSigAll!(int,bool).assertEqual("ib");
  // type codes
  typeCode!int().assertEqual(cast(int)('i'));
  typeCode!bool().assertEqual(cast(int)('b'));
  typeCode!(Tuple!(int, string))().assertEqual(cast(int)('r'));
  // ctfe-capable
  static string sig = typeSig!ulong();
  sig.assertEqual("t");
  static string sig2 = typeSig!(Tuple!(int,string,string));
  sig2.assertEqual("(iss)"); 
  static string sig3 = typeSigAll!(int,string,string);
  sig3.assertEqual("iss"); 
}

