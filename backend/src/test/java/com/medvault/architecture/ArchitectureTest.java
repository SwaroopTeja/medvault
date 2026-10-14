package com.medvault.architecture;

import com.medvault.user.PatientHealthInfo;
import com.medvault.user.PatientProfile;
import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.base.DescribedPredicate;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

import static com.tngtech.archunit.core.domain.JavaClass.Predicates.equivalentTo;
import static com.tngtech.archunit.core.domain.JavaClass.Predicates.resideInAnyPackage;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

@AnalyzeClasses(packages = "com.medvault", importOptions = ImportOption.DoNotIncludeTests.class)
public class ArchitectureTest {

    // One combined predicate, so there is no ambiguity about how rules are OR-ed.
    private static final DescribedPredicate<JavaClass> RESTRICTED_FOR_ADMIN =
            resideInAnyPackage("..medvault.document..", "..medvault.sharing..")
                    .or(equivalentTo(PatientHealthInfo.class))
                    .or(equivalentTo(PatientProfile.class));

    @ArchTest
    public static final ArchRule adminIsIsolatedFromMedicalData =
            noClasses()
                    .that().resideInAPackage("..medvault.admin..")
                    .should().dependOnClassesThat(RESTRICTED_FOR_ADMIN)
                    .because("Admin must never depend on document, sharing, PatientHealthInfo or PatientProfile");

    // Entities hold wrapped keys, storage keys and password hashes. Controllers must return DTOs.
    // allowEmptyShould: there are no controllers yet. Remove it once the first controller exists.
    @ArchTest
    public static final ArchRule controllersNeverTouchEntities =
            noClasses()
                    .that().areAnnotatedWith(org.springframework.web.bind.annotation.RestController.class)
                    .should().dependOnClassesThat().areAnnotatedWith(jakarta.persistence.Entity.class)
                    .because("Controllers must use DTOs, never JPA entities")
                    .allowEmptyShould(true);
}