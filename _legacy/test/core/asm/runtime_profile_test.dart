/// Tests for RuntimeProfile enum per DDD §3.3.
library;

import 'package:test/test.dart';
import 'package:flowbrain_core/src/core/asm/runtime_profile.dart';
import 'package:flowbrain_core/src/core/asm/errors.dart';

void main() {
  group('RuntimeProfile', () {
    group('needsFactGraph', () {
      test('full needs fact graph', () {
        expect(RuntimeProfile.full.needsFactGraph, isTrue);
      });

      test('skillLlmRag needs fact graph', () {
        expect(RuntimeProfile.skillLlmRag.needsFactGraph, isTrue);
      });

      test('readOnly needs fact graph', () {
        expect(RuntimeProfile.readOnly.needsFactGraph, isTrue);
      });

      test('ingestOnly needs fact graph', () {
        expect(RuntimeProfile.ingestOnly.needsFactGraph, isTrue);
      });

      test('skillLlm does not need fact graph', () {
        expect(RuntimeProfile.skillLlm.needsFactGraph, isFalse);
      });

      test('skillLlmMcp does not need fact graph', () {
        expect(RuntimeProfile.skillLlmMcp.needsFactGraph, isFalse);
      });
    });

    group('needsSkill', () {
      test('full needs skill', () {
        expect(RuntimeProfile.full.needsSkill, isTrue);
      });

      test('skillLlm needs skill', () {
        expect(RuntimeProfile.skillLlm.needsSkill, isTrue);
      });

      test('skillLlmMcp needs skill', () {
        expect(RuntimeProfile.skillLlmMcp.needsSkill, isTrue);
      });

      test('skillLlmRag needs skill', () {
        expect(RuntimeProfile.skillLlmRag.needsSkill, isTrue);
      });

      test('readOnly does not need skill', () {
        expect(RuntimeProfile.readOnly.needsSkill, isFalse);
      });

      test('ingestOnly does not need skill', () {
        expect(RuntimeProfile.ingestOnly.needsSkill, isFalse);
      });
    });

    group('needsProfile', () {
      test('only full needs profile', () {
        expect(RuntimeProfile.full.needsProfile, isTrue);
        for (final p in RuntimeProfile.values.where((v) => v != RuntimeProfile.full)) {
          expect(p.needsProfile, isFalse, reason: '${p.name} should not need profile');
        }
      });
    });

    group('needsPhilosophy', () {
      test('only full needs philosophy', () {
        expect(RuntimeProfile.full.needsPhilosophy, isTrue);
        for (final p in RuntimeProfile.values.where((v) => v != RuntimeProfile.full)) {
          expect(p.needsPhilosophy, isFalse, reason: '${p.name} should not need philosophy');
        }
      });
    });

    group('needsOps', () {
      test('only full needs ops', () {
        expect(RuntimeProfile.full.needsOps, isTrue);
        for (final p in RuntimeProfile.values.where((v) => v != RuntimeProfile.full)) {
          expect(p.needsOps, isFalse, reason: '${p.name} should not need ops');
        }
      });
    });

    group('requiredPorts', () {
      test('full has LlmPort and StoragePort', () {
        final ports = RuntimeProfile.full.requiredPorts;
        expect(ports, contains('LlmPort'));
        expect(ports, contains('StoragePort'));
        expect(ports, contains('EventPort'));
      });

      test('skillLlm requires LlmPort, SkillRuntimePort, SkillRegistryPort, StoragePort', () {
        expect(
          RuntimeProfile.skillLlm.requiredPorts,
          unorderedEquals(['LlmPort', 'SkillRuntimePort', 'SkillRegistryPort', 'StoragePort']),
        );
      });

      test('skillLlmMcp adds McpPort', () {
        final ports = RuntimeProfile.skillLlmMcp.requiredPorts;
        expect(ports, contains('McpPort'));
        expect(ports, contains('LlmPort'));
      });

      test('skillLlmRag adds RetrievalPort and ContextBundlePort', () {
        final ports = RuntimeProfile.skillLlmRag.requiredPorts;
        expect(ports, contains('RetrievalPort'));
        expect(ports, contains('ContextBundlePort'));
      });

      test('readOnly requires only data ports', () {
        expect(
          RuntimeProfile.readOnly.requiredPorts,
          unorderedEquals(['FactsPort', 'ClaimsPort', 'EntitiesPort', 'StoragePort']),
        );
      });

      test('ingestOnly requires evidence and facts', () {
        expect(
          RuntimeProfile.ingestOnly.requiredPorts,
          unorderedEquals(['EvidencePort', 'FactsPort', 'CandidatesPort', 'StoragePort']),
        );
      });
    });

    group('fromString', () {
      test('parses exact enum names', () {
        expect(RuntimeProfile.fromString('full'), RuntimeProfile.full);
        expect(RuntimeProfile.fromString('skillLlm'), RuntimeProfile.skillLlm);
        expect(RuntimeProfile.fromString('readOnly'), RuntimeProfile.readOnly);
        expect(RuntimeProfile.fromString('ingestOnly'), RuntimeProfile.ingestOnly);
      });

      test('parses snake_case variants', () {
        expect(RuntimeProfile.fromString('skill_llm'), RuntimeProfile.skillLlm);
        expect(RuntimeProfile.fromString('skill_llm_mcp'), RuntimeProfile.skillLlmMcp);
        expect(RuntimeProfile.fromString('skill_llm_rag'), RuntimeProfile.skillLlmRag);
        expect(RuntimeProfile.fromString('read_only'), RuntimeProfile.readOnly);
        expect(RuntimeProfile.fromString('ingest_only'), RuntimeProfile.ingestOnly);
      });

      test('throws ValidationError for unknown profile', () {
        expect(
          () => RuntimeProfile.fromString('nonexistent'),
          throwsA(isA<ValidationError>()),
        );
      });
    });

    test('has exactly 6 values', () {
      expect(RuntimeProfile.values.length, 6);
    });
  });
}
