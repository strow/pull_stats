function pull_stats_airibrad_rand_eval(year, filter);

%**************************************************
% need to make this work on daily concat files: look for loop over
% granules, this will need to be removed. Also break out by fov
% (add loop and index over p.ifov)
%
% following the 'file in; file out' standard, this routine will
% read in ONE daily concatenated rtp file and calculate its
% stats. There will be a driver function above this that will feed
% rtp file paths to this routine and can provide for slurm indexing
% and chunking
%**************************************************

addpath /asl/matlib/h4tools
addpath /asl/rtp_prod/airs/utils
addpath ~/git/rtp_prod2/util
addpath /home/sergio/MATLABCODE/PLOTTER  %
                                         % equal_area_spherical_bands
addpath /asl/matlib/rtptools  % mmwater_rtp.m

trace.RunDate = datetime('now','TimeZone','local','Format', ...
                         'd-MMM-y HH:mm:ss Z');

cstr =[ 'bits1-4=NEdT[0.08 0.12 0.15 0.20 0.25 0.30 0.35 0.4 0.5 0.6 0.7' ...
  ' 0.8 1.0 2.0 4.0 nan]; bit5=Aside[0=off,1=on]; bit6=Bside[0=off,1=on];' ...
  ' bits7-8=calflag&calchansummary[0=OK, 1=DCR, 2=moon, 3=other]' ];

basedir = fullfile('/asl/data/rtp_airibrad_v5/', ...
                   int2str(year), 'random');
dayfiles = dir(fullfile(basedir, 'era_airibrad*_random.rtp'));
fprintf(1,'>>> numfiles = %d\n', length(dayfiles));

% calculate latitude bins
nbins=20; % gives 2N+1 element array of lat bin boundaries
latbins = equal_area_spherical_bands(nbins);
nlatbins = length(latbins);

iday = 1;
% for giday = 1:50:length(dayfiles)
for giday = 1:length(dayfiles)
   fprintf(1, '>>> year = %d  :: giday = %d\n', year, giday);
   a = dir(fullfile(basedir,dayfiles(giday).name));
   if a.bytes > 100000
      [h,ha,p,pa] = rtpread(fullfile(basedir,dayfiles(giday).name));
      f = h.vchan;  % AIRS proper frequencies

      % sanity check on p.robs1 as read in. (There have been
      % instances where this array is short on the spectral
      % dimension which fails in rad2bt. We trap for this here)
      obs = size(p.robs1);
      chans = size(f);
      if obs(1) ~= chans(1)
          fprintf(2, ['**>> ERROR: obs/vchan spectral channel ' ...
                      'mismatch in %s. Bypassing day.\n'], dayfiles(giday).name);
          continue;
      end
      
% $$$       % get column water
% $$$       mmwater = mmwater_rtp(h, p);

      switch filter
        case 1
          k = find(p.iudef(4,:) == 68); % descending node (night)
          sDescriptor='_desc';
        case 2
          k = find(p.iudef(4,:) == 68 & p.landfrac == 0); % descending
                                                     % node (night) ocean
          sDescriptor='_desc_ocean';
        case 3
          k = find(p.iudef(4,:) == 68 & p.landfrac == 1); % descending node
                                                        % (night), land
          sDescriptor='_desc_land';
        case 4
          k = find(p.iudef(4,:) == 65); % ascending node (day)
          sDescriptor='_asc';
        case 5
          k = find(p.iudef(4,:) == 65 & p.landfrac == 0); % ascending node
                                                         % (day), ocean
          sDescriptor='_asc_ocean';
        case 6
          k = find(p.iudef(4,:) == 65 & p.landfrac == 1); % ascending node
                                                        % (day), land
          sDescriptor='_asc_land';
        case 7
          k = find(p.iudef(4,:) == 68 & p.rlat > -5 & p.rlat < 5 & ...
                   p.rlon > -170 & p.rlon < -90);
          sDescriptor='_elnino3';
      end

      pp = rtp_sub_prof(p, k);
% $$$       mmwater = mmwater(k);

      % Initialize counts
      [nedt,ab,ical] = calnum_to_data(p.calflag,cstr);
      n = length(p.rlat);
      count_all = ones(2378,n);
      for i=1:2378
         % Find bad channels
         k = find( p.robs1(i,:) == -9999 | ical(i,:) ~= 0 | nedt(i,:) > 1);
%          % These are the good channels
%          kg = setdiff(1:n,k);
% NaN's for bad channels
         pp.robs1(i,k) = NaN;
         pp.rcalc(i,k) = NaN;
         pp.sarta_rclearcalc(i,k) = NaN;
         count_all(i,k) = 0;
      end

      % Loop over latitude bins
      for ilat = 1:nlatbins-1
          % subset based on latitude bin
          inbin = find(pp.rlat > latbins(ilat) & pp.rlat <= ...
                     latbins(ilat+1));
          p = rtp_sub_prof(pp,inbin);
          bincount = count_all(:,inbin); 
% $$$           binwater = mmwater(inbin);
          
% Radiance mean and std
         r  = p.robs1;
         rc = p.rcalc;
         rclear = p.sarta_rclearcalc;
         
% B(T) bias mean and std
% $$$          bto = real(rad2bt(f,robs));
% $$$          btcloud = real(rad2bt(f,rcloud));
% $$$          btclear = real(rad2bt(f,rclear));
% $$$          btobs(iday,ilat,:) = nanmean(bto,2);
% $$$          btcldcal(iday,ilat,:) = nanmean(btcloud,2);
% $$$          btclrcal(iday,ilat,:) = nanmean(btclear,2);
% $$$          bias_clr(iday,ilat,:)  = nanmean(bto-btclear,2);
% $$$          bias_std_clr(iday,ilat,:) = nanstd(bto-btclear,0,2);
% $$$          bias_cld(iday,ilat,:)  = nanmean(bto-btcloud,2);
% $$$          bias_std_cld(iday,ilat,:) = nanstd(bto-btcloud,0,2);
% $$$          mmwater_mean(iday,ilat) = nanmean(binwater);
         robs(iday,ilat,:) = nanmean(r,2);
         rcal(iday,ilat,:) = nanmean(rc,2);
         rclrcal(iday,ilat,:) = nanmean(rclear,2);
         lat_mean(iday,ilat) = nanmean(p.rlat);
         lon_mean(iday,ilat) = nanmean(p.rlon);
         solzen_mean(iday,ilat) = nanmean(p.solzen);
         rtime_mean(iday,ilat)  = nanmean(p.rtime);
         count(iday,ilat,:) = sum(bincount,2)';
         stemp_mean(iday,ilat) = nanmean(p.stemp);
         ptemp_mean(iday,ilat,:) = nanmean(p.ptemp,2);
         gas1_mean(iday,ilat,:) = nanmean(p.gas_1,2);
         gas3_mean(iday,ilat,:) = nanmean(p.gas_3,2);
         spres_mean(iday,ilat) = nanmean(p.spres);
         nlevs_mean(iday,ilat) = nanmean(p.nlevs);
         iudef4_mean(iday,ilat) = nanmean(p.iudef(4,:));
         satzen_mean(iday,ilat) = nanmean(p.satzen);
         plevs_mean(iday,ilat,:) = nanmean(p.plevs,2);
         end  % end loop over latitudes
         iday = iday + 1
   end % if a.bytes > 1000000
end  % giday
eval_str = ['save /home/sbuczko1/testoutput/2015' ...
            '/airs/random/rtp_airibrad_rad_'  int2str(year) '_random' ...
            sDescriptor ' robs rcal rclrcal ' ...
            '*_mean count latbins trace'];
% $$$ btobs btcldcal btclrcal bias_std_clr
eval(eval_str);
