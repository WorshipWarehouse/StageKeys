// Standalone adaptation of Airwindows CreamCoat (MIT), Chris Johnson.
// Pinned upstream: 7623a1c14b012a1a6407bb0e3ba252d1f027a823.
// DSP equations and delay tables retained from processDoubleReplacing.
// Host adaptation: C state, deterministic noise seeds, cached preparation,
// in-place float I/O. No VST SDK or proprietary Sunday Keys code included.
#include "CreamCoat.h"
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
enum { predelay = 15000 };

enum { kshortA = 350 };
enum { kshortB = 1710 };
enum { kshortC = 1610 };
enum { kshortD = 835 };
enum { kshortE = 700 };
enum { kshortF = 1260 };
enum { kshortG = 1110 };
enum { kshortH = 1768 };
enum { kshortI = 280 };
enum { kshortJ = 2645 };
enum { kshortK = 1410 };
enum { kshortL = 1175 };
enum { kshortM = 12 };
enum { kshortN = 3110 };
enum { kshortO = 120 };
enum { kshortP = 2370 };

	enum {
		bez_AL,
		bez_AR,
		bez_BL,
		bez_BR,
		bez_CL,
		bez_CR,
		bez_InL,
		bez_InR,
		bez_UnInL,
		bez_UnInR,
		bez_SampL,
		bez_SampR,
		bez_cycle,
		bez_total
	}; //the new undersampling. bez signifies the bezier curve reconstruction

struct SKCreamCoat {
	double aAL[kshortA+5];
	double aBL[kshortB+5];
	double aCL[kshortC+5];
	double aDL[kshortD+5];
	double aEL[kshortE+5];
	double aFL[kshortF+5];
	double aGL[kshortG+5];
	double aHL[kshortH+5];
	double aIL[kshortI+5];
	double aJL[kshortJ+5];
	double aKL[kshortK+5];
	double aLL[kshortL+5];
	double aML[kshortM+5];
	double aNL[kshortN+5];
	double aOL[kshortO+5];
	double aPL[kshortP+5];

	double aAR[kshortA+5];
	double aBR[kshortB+5];
	double aCR[kshortC+5];
	double aDR[kshortD+5];
	double aER[kshortE+5];
	double aFR[kshortF+5];
	double aGR[kshortG+5];
	double aHR[kshortH+5];
	double aIR[kshortI+5];
	double aJR[kshortJ+5];
	double aKR[kshortK+5];
	double aLR[kshortL+5];
	double aMR[kshortM+5];
	double aNR[kshortN+5];
	double aOR[kshortO+5];
	double aPR[kshortP+5];

	double aZL[predelay+5];
	double aZR[predelay+5];

	double feedbackAL;
	double feedbackBL;
	double feedbackCL;
	double feedbackDL;

	double feedbackDR;
	double feedbackHR;
	double feedbackLR;
	double feedbackPR;

	double previousAL;
	double previousBL;
	double previousCL;
	double previousDL;
	double previousEL;

	double previousAR;
	double previousBR;
	double previousCR;
	double previousDR;
	double previousER;

	int countAL;
	int countBL;
	int countCL;
	int countDL;
	int countEL;
	int countFL;
	int countGL;
	int countHL;
	int countIL;
	int countJL;
	int countKL;
	int countLL;
	int countML;
	int countNL;
	int countOL;
	int countPL;

	int countAR;
	int countBR;
	int countCR;
	int countDR;
	int countER;
	int countFR;
	int countGR;
	int countHR;
	int countIR;
	int countJR;
	int countKR;
	int countLR;
	int countMR;
	int countNR;
	int countOR;
	int countPR;

	int countZ;

	int shortA;
	int shortB;
	int shortC;
	int shortD;
	int shortE;
	int shortF;
	int shortG;
	int shortH;
	int shortI;
	int shortJ;
	int shortK;
	int shortL;
	int shortM;
	int shortN;
	int shortO;
	int shortP;

	int prevclearcoat;

	double bez[bez_total];

    float A;
    float B;
    float C;
    float D;
    float E;

	uint32_t fpdL;
	uint32_t fpdR;

 double rate, regen, derez, wet, dry; int adjPredelay;
};
void sk_cream_reset(SKCreamCoat*s) {double rate=s->rate;memset(s,0,sizeof(*s));s->rate=rate;
	s->A = 0.5;
	s->B = 0.5;
	s->C = 1.0;
	s->D = 0.0;
	s->E = 0.25;

	for(int count = 0; count < kshortA+2; count++) {s->aAL[count] = 0.0; s->aAR[count] = 0.0;}
	for(int count = 0; count < kshortB+2; count++) {s->aBL[count] = 0.0; s->aBR[count] = 0.0;}
	for(int count = 0; count < kshortC+2; count++) {s->aCL[count] = 0.0; s->aCR[count] = 0.0;}
	for(int count = 0; count < kshortD+2; count++) {s->aDL[count] = 0.0; s->aDR[count] = 0.0;}
	for(int count = 0; count < kshortE+2; count++) {s->aEL[count] = 0.0; s->aER[count] = 0.0;}
	for(int count = 0; count < kshortF+2; count++) {s->aFL[count] = 0.0; s->aFR[count] = 0.0;}
	for(int count = 0; count < kshortG+2; count++) {s->aGL[count] = 0.0; s->aGR[count] = 0.0;}
	for(int count = 0; count < kshortH+2; count++) {s->aHL[count] = 0.0; s->aHR[count] = 0.0;}
	for(int count = 0; count < kshortI+2; count++) {s->aIL[count] = 0.0; s->aIR[count] = 0.0;}
	for(int count = 0; count < kshortJ+2; count++) {s->aJL[count] = 0.0; s->aJR[count] = 0.0;}
	for(int count = 0; count < kshortK+2; count++) {s->aKL[count] = 0.0; s->aKR[count] = 0.0;}
	for(int count = 0; count < kshortL+2; count++) {s->aLL[count] = 0.0; s->aLR[count] = 0.0;}
	for(int count = 0; count < kshortM+2; count++) {s->aML[count] = 0.0; s->aMR[count] = 0.0;}
	for(int count = 0; count < kshortN+2; count++) {s->aNL[count] = 0.0; s->aNR[count] = 0.0;}
	for(int count = 0; count < kshortO+2; count++) {s->aOL[count] = 0.0; s->aOR[count] = 0.0;}
	for(int count = 0; count < kshortP+2; count++) {s->aPL[count] = 0.0; s->aPR[count] = 0.0;}

	for(int count = 0; count < predelay+2; count++) {s->aZL[count] = 0.0; s->aZR[count] = 0.0;}

	s->feedbackAL = 0.0;
	s->feedbackBL = 0.0;
	s->feedbackCL = 0.0;
	s->feedbackDL = 0.0;

	s->previousAL = 0.0;
	s->previousBL = 0.0;
	s->previousCL = 0.0;
	s->previousDL = 0.0;
	s->previousEL = 0.0;

	s->feedbackDR = 0.0;
	s->feedbackHR = 0.0;
	s->feedbackLR = 0.0;
	s->feedbackPR = 0.0;

	s->previousAR = 0.0;
	s->previousBR = 0.0;
	s->previousCR = 0.0;
	s->previousDR = 0.0;
	s->previousER = 0.0;

	s->countAL = 1;
	s->countBL = 1;
	s->countCL = 1;
	s->countDL = 1;
	s->countEL = 1;
	s->countFL = 1;
	s->countGL = 1;
	s->countHL = 1;
	s->countIL = 1;
	s->countJL = 1;
	s->countKL = 1;
	s->countLL = 1;
	s->countML = 1;
	s->countNL = 1;
	s->countOL = 1;
	s->countPL = 1;

	s->countAR = 1;
	s->countBR = 1;
	s->countCR = 1;
	s->countDR = 1;
	s->countER = 1;
	s->countFR = 1;
	s->countGR = 1;
	s->countHR = 1;
	s->countIR = 1;
	s->countJR = 1;
	s->countKR = 1;
	s->countLR = 1;
	s->countMR = 1;
	s->countNR = 1;
	s->countOR = 1;
	s->countPR = 1;

	s->countZ = 1;

	s->shortA = 336;
	s->shortB = 1660;
	s->shortC = 386;
	s->shortD = 623;
	s->shortE = 693;
	s->shortF = 1079;
	s->shortG = 891;
	s->shortH = 1574;
	s->shortI = 24;
	s->shortJ = 2641;
	s->shortK = 1239;
	s->shortL = 775;
	s->shortM = 11;
	s->shortN = 3104;
	s->shortO = 55;
	s->shortP = 2366;
	s->prevclearcoat = -1;

	for (int x = 0; x < bez_total; x++) s->bez[x] = 0.0;
	s->bez[bez_cycle] = 1.0;


 s->fpdL=0x12345678; s->fpdR=0x87654321;
}
SKCreamCoat *sk_cream_create(double rate) {if(!isfinite(rate)||rate<8000||rate>384000)return NULL;SKCreamCoat*s=calloc(1,sizeof(*s));if(s){s->rate=rate;sk_cream_reset(s);}return s;}
void sk_cream_destroy(SKCreamCoat*s){free(s);}
void sk_cream_configure(SKCreamCoat*s,float size,float reflectivity,float quality,float predelayAmount) {
 s->A=fminf(1,fmaxf(0,size));s->B=fminf(1,fmaxf(0,reflectivity));s->C=fminf(1,fmaxf(0,quality));s->D=fminf(1,fmaxf(0,predelayAmount));s->E=1;
	double overallscale = 1.0;
	overallscale /= 44100.0;
	overallscale *= s->rate;

	int clearcoat = (int)( s->A * 16.999 );
	if (clearcoat != s->prevclearcoat) {
		for(int count = 0; count < kshortA+2; count++) {s->aAL[count] = 0.0; s->aAR[count] = 0.0;}
		for(int count = 0; count < kshortB+2; count++) {s->aBL[count] = 0.0; s->aBR[count] = 0.0;}
		for(int count = 0; count < kshortC+2; count++) {s->aCL[count] = 0.0; s->aCR[count] = 0.0;}
		for(int count = 0; count < kshortD+2; count++) {s->aDL[count] = 0.0; s->aDR[count] = 0.0;}
		for(int count = 0; count < kshortE+2; count++) {s->aEL[count] = 0.0; s->aER[count] = 0.0;}
		for(int count = 0; count < kshortF+2; count++) {s->aFL[count] = 0.0; s->aFR[count] = 0.0;}
		for(int count = 0; count < kshortG+2; count++) {s->aGL[count] = 0.0; s->aGR[count] = 0.0;}
		for(int count = 0; count < kshortH+2; count++) {s->aHL[count] = 0.0; s->aHR[count] = 0.0;}
		for(int count = 0; count < kshortI+2; count++) {s->aIL[count] = 0.0; s->aIR[count] = 0.0;}
		for(int count = 0; count < kshortJ+2; count++) {s->aJL[count] = 0.0; s->aJR[count] = 0.0;}
		for(int count = 0; count < kshortK+2; count++) {s->aKL[count] = 0.0; s->aKR[count] = 0.0;}
		for(int count = 0; count < kshortL+2; count++) {s->aLL[count] = 0.0; s->aLR[count] = 0.0;}
		for(int count = 0; count < kshortM+2; count++) {s->aML[count] = 0.0; s->aMR[count] = 0.0;}
		for(int count = 0; count < kshortN+2; count++) {s->aNL[count] = 0.0; s->aNR[count] = 0.0;}
		for(int count = 0; count < kshortO+2; count++) {s->aOL[count] = 0.0; s->aOR[count] = 0.0;}
		for(int count = 0; count < kshortP+2; count++) {s->aPL[count] = 0.0; s->aPR[count] = 0.0;}
		s->countAL = 1;
		s->countBL = 1;
		s->countCL = 1;
		s->countDL = 1;
		s->countEL = 1;
		s->countFL = 1;
		s->countGL = 1;
		s->countHL = 1;
		s->countIL = 1;
		s->countJL = 1;
		s->countKL = 1;
		s->countLL = 1;
		s->countML = 1;
		s->countNL = 1;
		s->countOL = 1;
		s->countPL = 1;

		s->countAR = 1;
		s->countBR = 1;
		s->countCR = 1;
		s->countDR = 1;
		s->countER = 1;
		s->countFR = 1;
		s->countGR = 1;
		s->countHR = 1;
		s->countIR = 1;
		s->countJR = 1;
		s->countKR = 1;
		s->countLR = 1;
		s->countMR = 1;
		s->countNR = 1;
		s->countOR = 1;
		s->countPR = 1;
		switch (clearcoat)
		{
			case 0:
				s->shortA = 65; s->shortB = 124; s->shortC = 83; s->shortD = 180; s->shortE = 200; s->shortF = 291; s->shortG = 108; s->shortH = 189; s->shortI = 73; s->shortJ = 410; s->shortK = 479; s->shortL = 310; s->shortM = 11; s->shortN = 928; s->shortO = 23; s->shortP = 654; break; //5 to 51 ms, 96 seat room. Scarcity, 1 in 125324
				//Short96
			case 1:
				s->shortA = 114; s->shortB = 205; s->shortC = 498; s->shortD = 195; s->shortE = 205; s->shortF = 318; s->shortG = 143; s->shortH = 254; s->shortI = 64; s->shortJ = 721; s->shortK = 512; s->shortL = 324; s->shortM = 11; s->shortN = 782; s->shortO = 26; s->shortP = 394; break; //7 to 52 ms, 107 seat club. Scarcity, 1 in 65537
				//Short107
			case 2:
				s->shortA = 118; s->shortB = 272; s->shortC = 292; s->shortD = 145; s->shortE = 200; s->shortF = 241; s->shortG = 204; s->shortH = 504; s->shortI = 50; s->shortJ = 678; s->shortK = 424; s->shortL = 412; s->shortM = 11; s->shortN = 1124; s->shortO = 47; s->shortP = 766; break; //8 to 58 ms, 135 seat club. Scarcity, 1 in 196272
				//Short135
			case 3:
				s->shortA = 19; s->shortB = 474; s->shortC = 301; s->shortD = 275; s->shortE = 260; s->shortF = 321; s->shortG = 371; s->shortH = 571; s->shortI = 50; s->shortJ = 410; s->shortK = 697; s->shortL = 414; s->shortM = 11; s->shortN = 986; s->shortO = 47; s->shortP = 522; break; //7 to 61 ms, 143 seat club. Scarcity, 1 in 165738
				//Short143
			case 4:
				s->shortA = 112; s->shortB = 387; s->shortC = 452; s->shortD = 289; s->shortE = 173; s->shortF = 476; s->shortG = 321; s->shortH = 593; s->shortI = 73; s->shortJ = 343; s->shortK = 829; s->shortL = 91; s->shortM = 11; s->shortN = 1055; s->shortO = 43; s->shortP = 862; break; //8 to 66 ms, 166 seat club. Scarcity, 1 in 158437
				//Short166
			case 5:
				s->shortA = 60; s->shortB = 368; s->shortC = 295; s->shortD = 272; s->shortE = 210; s->shortF = 284; s->shortG = 326; s->shortH = 830; s->shortI = 125; s->shortJ = 236; s->shortK = 737; s->shortL = 486; s->shortM = 11; s->shortN = 1178; s->shortO = 75; s->shortP = 902; break; //9 to 70 ms, 189 seat club. Scarcity, 1 in 94790
				//Short189
			case 6:
				s->shortA = 73; s->shortB = 311; s->shortC = 472; s->shortD = 251; s->shortE = 134; s->shortF = 509; s->shortG = 393; s->shortH = 591; s->shortI = 124; s->shortJ = 1070; s->shortK = 340; s->shortL = 525; s->shortM = 11; s->shortN = 1367; s->shortO = 75; s->shortP = 816; break; //7 to 79 ms, 225 seat club. Scarcity, 1 in 257803
				//Short225
			case 7:
				s->shortA = 159; s->shortB = 518; s->shortC = 514; s->shortD = 165; s->shortE = 275; s->shortF = 494; s->shortG = 296; s->shortH = 667; s->shortI = 75; s->shortJ = 1101; s->shortK = 116; s->shortL = 414; s->shortM = 11; s->shortN = 1261; s->shortO = 79; s->shortP = 998; break; //11 to 80 ms, 252 seat club. Scarcity, 1 in 175192
				//Short252
			case 8:
				s->shortA = 41; s->shortB = 741; s->shortC = 274; s->shortD = 59; s->shortE = 306; s->shortF = 332; s->shortG = 291; s->shortH = 767; s->shortI = 42; s->shortJ = 881; s->shortK = 959; s->shortL = 422; s->shortM = 11; s->shortN = 1237; s->shortO = 45; s->shortP = 958; break; //8 to 83 ms, 255 seat club. Scarcity, 1 in 185708
				//Short255
			case 9:
				s->shortA = 251; s->shortB = 437; s->shortC = 783; s->shortD = 189; s->shortE = 130; s->shortF = 272; s->shortG = 244; s->shortH = 761; s->shortI = 128; s->shortJ = 1190; s->shortK = 320; s->shortL = 491; s->shortM = 11; s->shortN = 1409; s->shortO = 58; s->shortP = 455; break; //10 to 93 ms, 323 seat club. Scarcity, 1 in 334044
				//Short323
			case 10:
				s->shortA = 316; s->shortB = 510; s->shortC = 1087; s->shortD = 349; s->shortE = 359; s->shortF = 74; s->shortG = 79; s->shortH = 1269; s->shortI = 34; s->shortJ = 693; s->shortK = 749; s->shortL = 511; s->shortM = 11; s->shortN = 1751; s->shortO = 93; s->shortP = 403; break; //9 to 110 ms, 427 seat theater. Scarcity, 1 in 200715
				//Short427
			case 11:
				s->shortA = 254; s->shortB = 651; s->shortC = 845; s->shortD = 316; s->shortE = 373; s->shortF = 267; s->shortG = 182; s->shortH = 857; s->shortI = 215; s->shortJ = 1535; s->shortK = 1127; s->shortL = 315; s->shortM = 11; s->shortN = 1649; s->shortO = 97; s->shortP = 829; break; //15 to 110 ms, 470 seat theater. Scarcity, 1 in 362673
				//Short470
			case 12:
				s->shortA = 113; s->shortB = 101; s->shortC = 673; s->shortD = 357; s->shortE = 340; s->shortF = 229; s->shortG = 278; s->shortH = 1008; s->shortI = 265; s->shortJ = 1890; s->shortK = 155; s->shortL = 267; s->shortM = 11; s->shortN = 2233; s->shortO = 116; s->shortP = 600; break; //11 to 131 ms, 606 seat theater. Scarcity, 1 in 238058
				//Short606
			case 13:
				s->shortA = 218; s->shortB = 1058; s->shortC = 862; s->shortD = 505; s->shortE = 297; s->shortF = 580; s->shortG = 532; s->shortH = 1387; s->shortI = 120; s->shortJ = 576; s->shortK = 1409; s->shortL = 473; s->shortM = 11; s->shortN = 1991; s->shortO = 76; s->shortP = 685; break; //14 to 132 ms, 643 seat theater. Scarcity, 1 in 193432
				//Short643
			case 14:
				s->shortA = 78; s->shortB = 760; s->shortC = 982; s->shortD = 528; s->shortE = 445; s->shortF = 1128; s->shortG = 130; s->shortH = 708; s->shortI = 22; s->shortJ = 2144; s->shortK = 354; s->shortL = 1169; s->shortM = 11; s->shortN = 2782; s->shortO = 58; s->shortP = 1515; break; //5 to 159 ms, 809 seat hall. Scarcity, 1 in 212274
				//Short809
			case 15:
				s->shortA = 330; s->shortB = 107; s->shortC = 1110; s->shortD = 371; s->shortE = 620; s->shortF = 143; s->shortG = 1014; s->shortH = 1763; s->shortI = 184; s->shortJ = 2068; s->shortK = 1406; s->shortL = 595; s->shortM = 11; s->shortN = 2639; s->shortO = 33; s->shortP = 1594; break; //10 to 171 ms, 984 seat hall. Scarcity, 1 in 226499
				//Short984
			case 16:
			default:
				s->shortA = 336; s->shortB = 1660; s->shortC = 386; s->shortD = 623; s->shortE = 693; s->shortF = 1079; s->shortG = 891; s->shortH = 1574; s->shortI = 24; s->shortJ = 2641; s->shortK = 1239; s->shortL = 775; s->shortM = 11; s->shortN = 3104; s->shortO = 55; s->shortP = 2366; break; //24 to 203 ms, 1541 seat hall. Scarcity, 1 in 275025
				//Short1541
		}
		s->prevclearcoat = clearcoat;
	}


	s->regen = (1.0-pow(1.0-s->B,2.0))*0.0625;
	s->derez = s->C/overallscale;
	if (s->derez < 0.0005) s->derez = 0.0005; if (s->derez > 1.0) s->derez = 1.0;
	s->derez = 1.0 / ((int)(1.0/s->derez));
	//this hard-locks s->derez to exact subdivisions of 1.0
	s->adjPredelay = predelay*s->D*s->derez;
	s->wet = s->E*2.0;
	s->dry = 2.0 - s->wet;
	if (s->wet > 1.0) s->wet = 1.0; else s->wet *= s->wet;
	if (s->wet < 0.0) s->wet = 0.0;
	if (s->dry > 1.0) s->dry = 1.0;
	if (s->dry < 0.0) s->dry = 0.0;
	//this reverb makes 50% full s->dry AND full s->wet, not crossfaded.
	//that's so it can be on submixes without cutting back s->dry channel when adjusted:
	//unless you go super heavy, you are only adjusting the added verb loudness.

}
void sk_cream_frame(SKCreamCoat*s,float*left,float*right){
		double inputSampleL = *left;
		double inputSampleR = *right;
		if (fabs(inputSampleL)<1.18e-23) inputSampleL = s->fpdL * 1.18e-17;
		if (fabs(inputSampleR)<1.18e-23) inputSampleR = s->fpdR * 1.18e-17;
		double drySampleL = inputSampleL;
		double drySampleR = inputSampleR;

		s->bez[bez_cycle] += s->derez;
		s->bez[bez_SampL] += ((inputSampleL+s->bez[bez_InL]) * s->derez);
		s->bez[bez_SampR] += ((inputSampleR+s->bez[bez_InR]) * s->derez);
		s->bez[bez_InL] = inputSampleL; s->bez[bez_InR] = inputSampleR;
		if (s->bez[bez_cycle] > 1.0) { //hit the end point and we do a reverb sample
			s->bez[bez_cycle] = 0.0;

			//predelay
			s->aZL[s->countZ] = s->bez[bez_SampL];
			s->aZR[s->countZ] = s->bez[bez_SampR];
			s->countZ++; if (s->countZ < 0 || s->countZ > s->adjPredelay) s->countZ = 0;
			s->bez[bez_SampL] = s->aZL[s->countZ-((s->countZ > s->adjPredelay)?s->adjPredelay+1:0)];
			s->bez[bez_SampR] = s->aZR[s->countZ-((s->countZ > s->adjPredelay)?s->adjPredelay+1:0)];
			//end predelay

			s->aAL[s->countAL] = (s->bez[bez_SampL]+s->bez[bez_UnInL]) + (s->feedbackAL * s->regen);
			s->aBL[s->countBL] = (s->bez[bez_SampL]+s->bez[bez_UnInL]) + (s->feedbackBL * s->regen);
			s->aCL[s->countCL] = (s->bez[bez_SampL]+s->bez[bez_UnInL]) + (s->feedbackCL * s->regen);
			s->aDL[s->countDL] = (s->bez[bez_SampL]+s->bez[bez_UnInL]) + (s->feedbackDL * s->regen);
			s->bez[bez_UnInL] = s->bez[bez_SampL];

			s->aDR[s->countDR] = (s->bez[bez_SampR]+s->bez[bez_UnInR]) + (s->feedbackDR * s->regen);
			s->aHR[s->countHR] = (s->bez[bez_SampR]+s->bez[bez_UnInR]) + (s->feedbackHR * s->regen);
			s->aLR[s->countLR] = (s->bez[bez_SampR]+s->bez[bez_UnInR]) + (s->feedbackLR * s->regen);
			s->aPR[s->countPR] = (s->bez[bez_SampR]+s->bez[bez_UnInR]) + (s->feedbackPR * s->regen);
			s->bez[bez_UnInR] = s->bez[bez_SampR];

			s->countAL++; if (s->countAL < 0 || s->countAL > s->shortA) s->countAL = 0;
			s->countBL++; if (s->countBL < 0 || s->countBL > s->shortB) s->countBL = 0;
			s->countCL++; if (s->countCL < 0 || s->countCL > s->shortC) s->countCL = 0;
			s->countDL++; if (s->countDL < 0 || s->countDL > s->shortD) s->countDL = 0;

			s->countDR++; if (s->countDR < 0 || s->countDR > s->shortD) s->countDR = 0;
			s->countHR++; if (s->countHR < 0 || s->countHR > s->shortH) s->countHR = 0;
			s->countLR++; if (s->countLR < 0 || s->countLR > s->shortL) s->countLR = 0;
			s->countPR++; if (s->countPR < 0 || s->countPR > s->shortP) s->countPR = 0;

			double outAL = s->aAL[s->countAL-((s->countAL > s->shortA)?s->shortA+1:0)];
			double outBL = s->aBL[s->countBL-((s->countBL > s->shortB)?s->shortB+1:0)];
			double outCL = s->aCL[s->countCL-((s->countCL > s->shortC)?s->shortC+1:0)];
			double outDL = s->aDL[s->countDL-((s->countDL > s->shortD)?s->shortD+1:0)];

			double outDR = s->aDR[s->countDR-((s->countDR > s->shortD)?s->shortD+1:0)];
			double outHR = s->aHR[s->countHR-((s->countHR > s->shortH)?s->shortH+1:0)];
			double outLR = s->aLR[s->countLR-((s->countLR > s->shortL)?s->shortL+1:0)];
			double outPR = s->aPR[s->countPR-((s->countPR > s->shortP)?s->shortP+1:0)];

			s->aEL[s->countEL] = outAL - (outBL + outCL + outDL);
			s->aFL[s->countFL] = outBL - (outAL + outCL + outDL);
			s->aGL[s->countGL] = outCL - (outAL + outBL + outDL);
			s->aHL[s->countHL] = outDL - (outAL + outBL + outCL);

			s->aCR[s->countCR] = outDR - (outHR + outLR + outPR);
			s->aGR[s->countGR] = outHR - (outDR + outLR + outPR);
			s->aKR[s->countKR] = outLR - (outDR + outHR + outPR);
			s->aOR[s->countOR] = outPR - (outDR + outHR + outLR);

			s->countEL++; if (s->countEL < 0 || s->countEL > s->shortE) s->countEL = 0;
			s->countFL++; if (s->countFL < 0 || s->countFL > s->shortF) s->countFL = 0;
			s->countGL++; if (s->countGL < 0 || s->countGL > s->shortG) s->countGL = 0;
			s->countHL++; if (s->countHL < 0 || s->countHL > s->shortH) s->countHL = 0;

			s->countCR++; if (s->countCR < 0 || s->countCR > s->shortC) s->countCR = 0;
			s->countGR++; if (s->countGR < 0 || s->countGR > s->shortG) s->countGR = 0;
			s->countKR++; if (s->countKR < 0 || s->countKR > s->shortK) s->countKR = 0;
			s->countOR++; if (s->countOR < 0 || s->countOR > s->shortO) s->countOR = 0;

			double outEL = s->aEL[s->countEL-((s->countEL > s->shortE)?s->shortE+1:0)];
			double outFL = s->aFL[s->countFL-((s->countFL > s->shortF)?s->shortF+1:0)];
			double outGL = s->aGL[s->countGL-((s->countGL > s->shortG)?s->shortG+1:0)];
			double outHL = s->aHL[s->countHL-((s->countHL > s->shortH)?s->shortH+1:0)];

			double outCR = s->aCR[s->countCR-((s->countCR > s->shortC)?s->shortC+1:0)];
			double outGR = s->aGR[s->countGR-((s->countGR > s->shortG)?s->shortG+1:0)];
			double outKR = s->aKR[s->countKR-((s->countKR > s->shortK)?s->shortK+1:0)];
			double outOR = s->aOR[s->countOR-((s->countOR > s->shortO)?s->shortO+1:0)];

			s->aIL[s->countIL] = outEL - (outFL + outGL + outHL);
			s->aJL[s->countJL] = outFL - (outEL + outGL + outHL);
			s->aKL[s->countKL] = outGL - (outEL + outFL + outHL);
			s->aLL[s->countLL] = outHL - (outEL + outFL + outGL);

			s->aBR[s->countBR] = outCR - (outGR + outKR + outOR);
			s->aFR[s->countFR] = outGR - (outCR + outKR + outOR);
			s->aJR[s->countJR] = outKR - (outCR + outGR + outOR);
			s->aNR[s->countNR] = outOR - (outCR + outGR + outKR);

			s->countIL++; if (s->countIL < 0 || s->countIL > s->shortI) s->countIL = 0;
			s->countJL++; if (s->countJL < 0 || s->countJL > s->shortJ) s->countJL = 0;
			s->countKL++; if (s->countKL < 0 || s->countKL > s->shortK) s->countKL = 0;
			s->countLL++; if (s->countLL < 0 || s->countLL > s->shortL) s->countLL = 0;

			s->countBR++; if (s->countBR < 0 || s->countBR > s->shortB) s->countBR = 0;
			s->countFR++; if (s->countFR < 0 || s->countFR > s->shortF) s->countFR = 0;
			s->countJR++; if (s->countJR < 0 || s->countJR > s->shortJ) s->countJR = 0;
			s->countNR++; if (s->countNR < 0 || s->countNR > s->shortN) s->countNR = 0;

			double outIL = s->aIL[s->countIL-((s->countIL > s->shortI)?s->shortI+1:0)];
			double outJL = s->aJL[s->countJL-((s->countJL > s->shortJ)?s->shortJ+1:0)];
			double outKL = s->aKL[s->countKL-((s->countKL > s->shortK)?s->shortK+1:0)];
			double outLL = s->aLL[s->countLL-((s->countLL > s->shortL)?s->shortL+1:0)];

			double outBR = s->aBR[s->countBR-((s->countBR > s->shortB)?s->shortB+1:0)];
			double outFR = s->aFR[s->countFR-((s->countFR > s->shortF)?s->shortF+1:0)];
			double outJR = s->aJR[s->countJR-((s->countJR > s->shortJ)?s->shortJ+1:0)];
			double outNR = s->aNR[s->countNR-((s->countNR > s->shortN)?s->shortN+1:0)];

			s->aML[s->countML] = outIL - (outJL + outKL + outLL);
			s->aNL[s->countNL] = outJL - (outIL + outKL + outLL);
			s->aOL[s->countOL] = outKL - (outIL + outJL + outLL);
			s->aPL[s->countPL] = outLL - (outIL + outJL + outKL);

			s->aAR[s->countAR] = outBR - (outFR + outJR + outNR);
			s->aER[s->countER] = outFR - (outBR + outJR + outNR);
			s->aIR[s->countIR] = outJR - (outBR + outFR + outNR);
			s->aMR[s->countMR] = outNR - (outBR + outFR + outJR);

			s->countML++; if (s->countML < 0 || s->countML > s->shortM) s->countML = 0;
			s->countNL++; if (s->countNL < 0 || s->countNL > s->shortN) s->countNL = 0;
			s->countOL++; if (s->countOL < 0 || s->countOL > s->shortO) s->countOL = 0;
			s->countPL++; if (s->countPL < 0 || s->countPL > s->shortP) s->countPL = 0;

			s->countAR++; if (s->countAR < 0 || s->countAR > s->shortA) s->countAR = 0;
			s->countER++; if (s->countER < 0 || s->countER > s->shortE) s->countER = 0;
			s->countIR++; if (s->countIR < 0 || s->countIR > s->shortI) s->countIR = 0;
			s->countMR++; if (s->countMR < 0 || s->countMR > s->shortM) s->countMR = 0;

			double outML = s->aML[s->countML-((s->countML > s->shortM)?s->shortM+1:0)];
			double outNL = s->aNL[s->countNL-((s->countNL > s->shortN)?s->shortN+1:0)];
			double outOL = s->aOL[s->countOL-((s->countOL > s->shortO)?s->shortO+1:0)];
			double outPL = s->aPL[s->countPL-((s->countPL > s->shortP)?s->shortP+1:0)];

			double outAR = s->aAR[s->countAR-((s->countAR > s->shortA)?s->shortA+1:0)];
			double outER = s->aER[s->countER-((s->countER > s->shortE)?s->shortE+1:0)];
			double outIR = s->aIR[s->countIR-((s->countIR > s->shortI)?s->shortI+1:0)];
			double outMR = s->aMR[s->countMR-((s->countMR > s->shortM)?s->shortM+1:0)];

			s->feedbackAL = outML - (outNL + outOL + outPL);
			s->feedbackDR = outAR - (outER + outIR + outMR);
			s->feedbackBL = outNL - (outML + outOL + outPL);
			s->feedbackHR = outER - (outAR + outIR + outMR);
			s->feedbackCL = outOL - (outML + outNL + outPL);
			s->feedbackLR = outIR - (outAR + outER + outMR);
			s->feedbackDL = outPL - (outML + outNL + outOL);
			s->feedbackPR = outMR - (outAR + outER + outIR);
			//which we need to feed back into the input again, a bit

			inputSampleL = (outML + outNL + outOL + outPL)/32.0;
			inputSampleR = (outAR + outER + outIR + outMR)/32.0;
			//and take the final combined sum of outputs, corrected for Householder gain and averaging

			s->bez[bez_CL] = s->bez[bez_BL];
			s->bez[bez_BL] = s->bez[bez_AL];
			s->bez[bez_AL] = inputSampleL;
			s->bez[bez_SampL] = 0.0;

			s->bez[bez_CR] = s->bez[bez_BR];
			s->bez[bez_BR] = s->bez[bez_AR];
			s->bez[bez_AR] = inputSampleR;
			s->bez[bez_SampR] = 0.0;
		}
		double CBL = (s->bez[bez_CL]*(1.0-s->bez[bez_cycle]))+(s->bez[bez_BL]*s->bez[bez_cycle]);
		double CBR = (s->bez[bez_CR]*(1.0-s->bez[bez_cycle]))+(s->bez[bez_BR]*s->bez[bez_cycle]);
		double BAL = (s->bez[bez_BL]*(1.0-s->bez[bez_cycle]))+(s->bez[bez_AL]*s->bez[bez_cycle]);
		double BAR = (s->bez[bez_BR]*(1.0-s->bez[bez_cycle]))+(s->bez[bez_AR]*s->bez[bez_cycle]);
		double CBAL = (s->bez[bez_BL]+(CBL*(1.0-s->bez[bez_cycle]))+(BAL*s->bez[bez_cycle]))*0.125;
		double CBAR = (s->bez[bez_BR]+(CBR*(1.0-s->bez[bez_cycle]))+(BAR*s->bez[bez_cycle]))*0.125;
		inputSampleL = CBAL;
		inputSampleR = CBAR;

		if (inputSampleL > 1.0) inputSampleL = 1.0;
		if (inputSampleL < -1.0) inputSampleL = -1.0;
		if (inputSampleR > 1.0) inputSampleR = 1.0;
		if (inputSampleR < -1.0) inputSampleR = -1.0;

		if (s->wet < 1.0) {inputSampleL *= s->wet; inputSampleR *= s->wet;}
		if (s->dry < 1.0) {drySampleL *= s->dry; drySampleR *= s->dry;}
		inputSampleL += drySampleL; inputSampleR += drySampleR;
		//this is our submix verb s->dry/s->wet: 0.5 is BOTH at FULL VOLUME
		//purpose is that, if you're adding verb, you're not altering other balances

		//begin 64 bit stereo floating point dither
		//int expon; frexp((double)inputSampleL, &expon);
		s->fpdL ^= s->fpdL << 13; s->fpdL ^= s->fpdL >> 17; s->fpdL ^= s->fpdL << 5;
		//inputSampleL += ((double(s->fpdL)-uint32_t(0x7fffffff)) * 1.1e-44l * pow(2,expon+62));
		//frexp((double)inputSampleR, &expon);
		s->fpdR ^= s->fpdR << 13; s->fpdR ^= s->fpdR >> 17; s->fpdR ^= s->fpdR << 5;
		//inputSampleR += ((double(s->fpdR)-uint32_t(0x7fffffff)) * 1.1e-44l * pow(2,expon+62));
		//end 64 bit stereo floating point dither

		*left = inputSampleL;
		*right = inputSampleR;
}
