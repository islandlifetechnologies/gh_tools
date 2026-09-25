import 'package:embed_annotation/embed_annotation.dart';

part 'pubspec.g.dart';

@EmbedLiteral('../../../pubspec.yaml')
const kPubspec = _$kPubspec;
