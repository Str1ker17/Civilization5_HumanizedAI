#pragma once

#ifndef HUMANIZED_AI_H
#define HUMANIZED_AI_H

#include "CvWeightedVector.h"

template<class T, unsigned int L, bool bPODType>
T HumanizedAIChoose(const CvPlayer& kPlayer, CvWeightedVector<T, L, bPODType>& kChoices, RandomNumberDelegate* pRandFcn, const char* szKind)
{
	int iSize = (int)kChoices.size();
	if(iSize == 0)
	{
		return kChoices.ChooseFromTopChoices(0, pRandFcn, szKind);
	}

	int iChosen = 0;
	int iMistakePercent = kPlayer.GetMistakePercent();
	if(iSize > 1 && iMistakePercent > 0 && (*pRandFcn)(100, szKind) < iMistakePercent)
	{
		int iLast = std::min(iSize, kPlayer.GetMistakeMaxRank());
		int iTotal = 0;
		for(int i = 1; i < iLast; i++)
		{
			iTotal += std::max(0, kChoices.GetWeight(i));
		}
		if(iTotal > 0)
		{
			int iRoll = (*pRandFcn)(iTotal, szKind);
			for(int i = 1; i < iLast; i++)
			{
				iRoll -= std::max(0, kChoices.GetWeight(i));
				if(iRoll < 0)
				{
					iChosen = i;
					break;
				}
			}
		}
	}

	kPlayer.LogMistakeChoice(szKind, iChosen, iSize, kChoices.GetWeight(0), kChoices.GetWeight(iChosen));
	return kChoices.GetElement(iChosen);
}

#endif
